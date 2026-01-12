# GitHub Actions Setup Guide

This repository includes a GitHub Action that automatically builds and pushes a Docker image to Docker Hub.

## Docker Hub Setup

1. **Create Docker Hub account** (if you don't have one)
   - Go to https://hub.docker.com/
   - Sign up or log in

2. **Create Access Token**
   - Go to Account Settings → Security → Access Tokens
   - Click "New Access Token"
   - Name: `github-actions-home-manager`
   - Permissions: Read, Write, Delete
   - Copy the token (you won't see it again!)

3. **Add Secrets to GitHub**
   - Go to your repository: https://github.com/brona90/home-manager
   - Settings → Secrets and variables → Actions
   - Click "New repository secret"
   
   Add two secrets:
   - Name: `DOCKERHUB_USERNAME`
     Value: `brona90`
   
   - Name: `DOCKERHUB_TOKEN`
     Value: [paste the access token from step 2]

## What the Action Does

On every push to `master`:
1. Checks out the code
2. Installs Nix with flakes enabled
3. Builds the Docker image using `nix build .#dockerImage`
4. Tags the image as:
   - `brona90/terminal:latest`
   - `brona90/terminal:YYYYMMDD` (date-stamped)
5. Pushes both tags to Docker Hub
6. Tests the image to verify tools are available

## Manual Trigger

You can also trigger the build manually:
1. Go to Actions tab in GitHub
2. Select "Build and Push Docker Image"
3. Click "Run workflow"
4. Select branch (master)
5. Click "Run workflow"

## Using the Published Image

Once published, anyone can use your terminal environment:

```bash
# Pull and run the latest version
docker run -it --rm brona90/terminal:latest

# Pull a specific date version
docker run -it --rm brona90/terminal:20260112

# Run with mounted SSH keys
docker run -it --rm \
  -v ~/.ssh:/home/gfoster/.ssh:ro \
  brona90/terminal:latest
```

## Troubleshooting

### Build fails with "unauthorized"
- Check that DOCKERHUB_USERNAME and DOCKERHUB_TOKEN secrets are set correctly
- Verify the token has write permissions

### Build fails with Nix errors
- Check that flake.nix is valid
- Test locally first: `nix build .#dockerImage`

### Image not appearing on Docker Hub
- Check the Actions tab for errors
- Verify you're pushing to master branch (PRs don't push)
- Check Docker Hub repository visibility settings

## Monitoring

- View build status: https://github.com/brona90/home-manager/actions
- View published images: https://hub.docker.com/r/brona90/terminal
