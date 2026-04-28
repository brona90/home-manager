#!/usr/bin/env python3
import socket, threading, os, subprocess, shutil, time, sys, struct, select

PKSIGN_MARKER = b"PKSIGN"
OK_NEWLINE = bytes([10]) + b"OK"
WSL_PS1 = os.path.expanduser("~/.local/bin/gpg_touch.ps1")
FALLBACK_GNUPGHOME = os.path.expanduser("~/.gnupg")

def get_win_user():
    return subprocess.check_output(
        ["/mnt/c/Windows/System32/cmd.exe", "/c", "echo %USERNAME%"],
        stderr=subprocess.DEVNULL, text=True
    ).strip()

def setup_ps1(win_user):
    dst = f"/mnt/c/Users/{win_user}/AppData/Local/Temp/gpg_touch.ps1"
    try:
        shutil.copy2(WSL_PS1, dst)
    except Exception:
        pass
    return f"C:/Users/{win_user}/AppData/Local/Temp/gpg_touch.ps1"

def start_touch_popup(win_ps1):
    return subprocess.Popen(
        ["/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe",
         "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", win_ps1],
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
    )

def get_win_gnupg(win_user):
    # Gpg4win stores runtime sockets in AppData\Local\gnupg, not .gnupg
    local_appdata = f"/mnt/c/Users/{win_user}/AppData/Local/gnupg"
    if os.path.exists(local_appdata):
        return local_appdata
    return f"/mnt/c/Users/{win_user}/.gnupg"

def read_win_agent(path):
    with open(path, "rb") as f:
        data = f.read()
    # Cygwin/MSYS2 format: b"!<socket >PORT s GUID\0"
    # GUID is 4 groups of 8 hex chars; each group is a little-endian uint32
    if data.startswith(b"!<socket >"):
        rest = data[len(b"!<socket >"):]
        port = int(rest[:rest.index(b" ")])
        guid = rest[rest.index(b" ") + 3:].rstrip(b"\x00").decode()
        nonce = b"".join(
            struct.pack("<I", int(g, 16)) for g in guid.split("-")
        )
        return port, nonce, True
    # Legacy Assuan format: PORT\n<16-byte-binary-nonce>
    port_end = data.index(10)
    port = int(data[:port_end])
    nonce = data[port_end+1:port_end+17]
    return port, nonce, False

def connect_win_agent(path):
    """Returns (socket, greeting) with handshake complete but greeting not yet forwarded."""
    port, nonce, is_cygwin = read_win_agent(path)
    s = socket.socket()
    s.settimeout(10)
    s.connect(("127.0.0.1", port))
    s.sendall(nonce)
    if is_cygwin:
        s.recv(16)  # nonce echo
        s.sendall(struct.pack("<III", os.getuid(), os.getgid(), os.getpid()))
        s.recv(12)  # server creds
    greeting = b""
    while b"OK" not in greeting and len(greeting) < 256:
        greeting += s.recv(64)
    if not greeting.startswith(b"OK"):
        s.close()
        raise ConnectionError(f"unexpected greeting: {greeting!r}")
    s.settimeout(None)
    return s, greeting

_card_cache = [None, 0.0]  # [result, timestamp]

# Fallback: persistent gpg-agent --server subprocess (stdin/stdout, no socket conflict)
_fb_proc = [None]
_fb_lock = threading.Lock()

def _probe_card(win_gnupg_path):
    # Connect to Windows agent and send SCD SERIALNO — fast and accurate
    sock_path = f"{win_gnupg_path}/S.gpg-agent"
    try:
        s, _ = connect_win_agent(sock_path)
        s.settimeout(5)
        s.sendall(b"SCD SERIALNO\n")
        resp = b""
        deadline = time.time() + 5
        while time.time() < deadline:
            chunk = s.recv(256)
            if not chunk:
                break
            resp += chunk
            if b"\nOK" in resp or b"\nERR" in resp:
                break
        try: s.close()
        except: pass
        return b"S SERIALNO" in resp
    except Exception:
        pass
    # Fallback: run gpg.exe --card-status
    try:
        result = subprocess.run(
            ["/mnt/c/Program Files/GnuPG/bin/gpg.exe", "--card-status"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
        )
        return b"Serial number" in result.stdout
    except Exception:
        return False

def card_available(win_gnupg_path):
    now = time.time()
    if _card_cache[0] is not None and now - _card_cache[1] < 3:
        return _card_cache[0]
    result = _probe_card(win_gnupg_path)
    _card_cache[0] = result
    _card_cache[1] = now
    return result

def _get_fb_proc():
    p = _fb_proc[0]
    if p is not None and p.poll() is None:
        return p
    nix_bin = os.path.expanduser("~/.nix-profile/bin")
    agent_bin = f"{nix_bin}/gpg-agent" if os.path.exists(f"{nix_bin}/gpg-agent") else (shutil.which("gpg-agent") or "gpg-agent")
    pinentry = f"{nix_bin}/pinentry-tty" if os.path.exists(f"{nix_bin}/pinentry-tty") else (shutil.which("pinentry-tty") or "pinentry-tty")
    env = dict(os.environ)
    env["GNUPGHOME"] = FALLBACK_GNUPGHOME
    log("starting fallback gpg-agent --server")
    p = subprocess.Popen(
        [agent_bin, "--server", "--homedir", FALLBACK_GNUPGHOME,
         "--pinentry-program", pinentry,
         "--allow-loopback-pinentry", "--disable-scdaemon",
         "--default-cache-ttl", "28800", "--max-cache-ttl", "86400"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        env=env
    )
    # Consume initial greeting
    greeting = b""
    while True:
        chunk = p.stdout.read(1)
        if not chunk:
            break
        greeting += chunk
        if greeting.endswith(b"\n") and (b"OK" in greeting or b"ERR" in greeting):
            break
    log(f"fallback agent ready, greeting={greeting!r}")
    _fb_proc[0] = p
    return p

def relay_fallback(client):
    with _fb_lock:
        try:
            proc = _get_fb_proc()
        except Exception as e:
            log(f"fallback agent start failed: {e}")
            try: client.close()
            except: pass
            return

        try:
            client.sendall(f"OK Pleased to meet you, process {proc.pid}\n".encode())
        except Exception:
            return

        client_done = threading.Event()

        def to_agent():
            try:
                while True:
                    d = client.recv(4096)
                    if not d:
                        break
                    proc.stdin.write(d)
                    proc.stdin.flush()
            except Exception:
                pass
            client_done.set()

        def from_agent():
            try:
                while not client_done.is_set():
                    r, _, _ = select.select([proc.stdout], [], [], 0.1)
                    if r:
                        d = os.read(proc.stdout.fileno(), 4096)
                        if not d:
                            break
                        client.sendall(d)
            except Exception:
                pass

        t1 = threading.Thread(target=to_agent, daemon=True)
        t2 = threading.Thread(target=from_agent, daemon=True)
        t1.start()
        t2.start()
        t1.join()
        client_done.set()
        t2.join(timeout=2)

        # RESET agent state for next session (preserves passphrase cache)
        try:
            proc.stdin.write(b"RESET\n")
            proc.stdin.flush()
            deadline = time.time() + 2
            buf = b""
            while time.time() < deadline:
                r, _, _ = select.select([proc.stdout], [], [], 0.5)
                if r:
                    buf += os.read(proc.stdout.fileno(), 256)
                    if b"OK" in buf or b"ERR" in buf:
                        break
        except Exception:
            pass

        try: client.close()
        except: pass

def log(msg):
    print(f"gpg-bridge: {msg}", file=sys.stderr, flush=True)

def handle(client, win_gnupg_path, win_ps1):
    avail = card_available(win_gnupg_path)
    log(f"card_available={avail}")
    if not avail:
        relay_fallback(client)
        return
    win_sock_path = f"{win_gnupg_path}/S.gpg-agent"

    popup = [None]
    win_lock = threading.Lock()
    client_lock = threading.Lock()

    def close_popup():
        p = popup[0]
        if p and p.poll() is None:
            p.terminate()

    win = None
    try:
        win, greeting = connect_win_agent(win_sock_path)
        log(f"connected to win agent, greeting={greeting!r}")
        with client_lock:
            client.sendall(greeting)

        def relay_win_to_client():
            popup_buf = b""
            pending = b""
            try:
                while True:
                    d = win.recv(4096)
                    if not d:
                        break
                    pending += d
                    out = b""
                    while b"\n" in pending:
                        line, pending = pending.split(b"\n", 1)
                        log(f"win→client: {line!r}")
                        if line.startswith(b"INQUIRE CONFIRM"):
                            if popup[0] is None:
                                popup[0] = start_touch_popup(win_ps1)
                            log("intercepting CONFIRM, sending D 1\\nEND\\n")
                            with win_lock:
                                try: win.sendall(b"D 1\nEND\n")
                                except Exception as e: log(f"CONFIRM sendall err: {e}")
                        elif line.startswith(b"INQUIRE PINENTRY_LAUNCHED"):
                            log("intercepting PINENTRY_LAUNCHED, sending END")
                            with win_lock:
                                try: win.sendall(b"END\n")
                                except Exception as e: log(f"PINENTRY_LAUNCHED sendall err: {e}")
                        else:
                            out += line + b"\n"
                    if out:
                        if popup[0]:
                            popup_buf += out
                            if OK_NEWLINE in popup_buf or popup_buf.startswith(b"OK"):
                                close_popup()
                                popup_buf = b""
                            elif len(popup_buf) > 128:
                                popup_buf = popup_buf[-10:]
                        with client_lock:
                            client.sendall(out)
            except Exception as e:
                log(f"relay_win_to_client exception: {e}")
            close_popup()
            try:
                client.shutdown(socket.SHUT_WR)
            except Exception:
                pass

        t = threading.Thread(target=relay_win_to_client, daemon=True)
        t.start()

        try:
            pksign_buf = b""
            client_pending = b""
            while True:
                d = client.recv(4096)
                if not d:
                    break
                client_pending += d
                while b"\n" in client_pending:
                    line, client_pending = client_pending.split(b"\n", 1)
                    log(f"client→win: {line!r}")
                    if line == b"OPTION pinentry-mode=loopback":
                        log("dropping loopback option, faking OK to client")
                        with client_lock:
                            client.sendall(b"OK\n")
                    else:
                        pksign_buf += line + b"\n"
                        if popup[0] is None and PKSIGN_MARKER in pksign_buf:
                            popup[0] = start_touch_popup(win_ps1)
                        if len(pksign_buf) > 1024:
                            pksign_buf = pksign_buf[-256:]
                        with win_lock:
                            win.sendall(line + b"\n")
        except Exception as e:
            log(f"client relay exception: {e}")
        try:
            win.shutdown(socket.SHUT_WR)
        except Exception:
            pass

        t.join(timeout=2)
    except Exception as e:
        log(f"handle exception: {e}")
    finally:
        close_popup()
        try: client.close()
        except Exception: pass
        try:
            if win: win.close()
        except Exception: pass

def main():
    _card_cache[0] = None
    _card_cache[1] = 0.0
    win_user = get_win_user()
    win_gnupg = get_win_gnupg(win_user)
    win_ps1 = setup_ps1(win_user)
    sock_path = os.popen("gpgconf --list-dirs agent-socket").read().strip()
    if not sock_path:
        print("Could not determine gpg-agent socket path", flush=True)
        return 1
    subprocess.run(["gpgconf", "--kill", "gpg-agent"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.makedirs(os.path.dirname(sock_path), exist_ok=True)
    if os.path.exists(sock_path):
        os.unlink(sock_path)
    server = socket.socket(socket.AF_UNIX)
    server.bind(sock_path)
    os.chmod(sock_path, 0o600)
    server.listen(5)
    print(f"GPG bridge listening on {sock_path}", flush=True)
    while True:
        client, _ = server.accept()
        threading.Thread(target=handle, args=(client, win_gnupg, win_ps1), daemon=True).start()

raise SystemExit(main())
