#!/bin/bash

# Configuration variables
LINUX_USER_PASSWORD="krish"
NGROK_AUTH_TOKEN="2SKcLerzezlK6RqZ46Qn94kvKlW_5dyB5HGL386Pgx8JrAaZ8"
NGROK_REGION="us"
PORT=8080
GOTTY_VERSION="v0.0.11"

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to clean up processes on exit
cleanup() {
    echo "Cleaning up..."
    pkill -f "gotty.*$PORT" 2>/dev/null
    pkill -f "ngrok.*$PORT" 2>/dev/null
}

# Set up trap for cleanup on script exit or interrupt
trap cleanup EXIT INT TERM

echo "### Installing dependencies ###"
# Check for required tools
for cmd in wget unzip curl; do
    if ! command_exists "$cmd"; then
        echo "Installing $cmd..."
        sudo apt-get update && sudo apt-get install -y "$cmd"
    fi
done

echo "### Installing ngrok ###"
if ! command_exists ngrok; then
    if ! wget -q -O ngrok.zip https://bin.equinox.io/c/4VmDzA7iaHb/ngrok-stable-linux-amd64.zip; then
        echo "❌ Failed to download ngrok"
        exit 1
    fi
    unzip -o ngrok.zip
    sudo mv ngrok /usr/local/bin/ngrok
    chmod +x /usr/local/bin/ngrok
    rm -f ngrok.zip
else
    echo "ngrok already installed"
fi

echo "### Configuring ngrok ###"
if ! /usr/local/bin/ngrok authtoken "$NGROK_AUTH_TOKEN" 2>/dev/null; then
    echo "❌ Failed to configure ngrok authtoken"
    exit 1
fi

echo "### Installing gotty ###"
if ! command_exists gotty; then
    if ! wget -q "https://github.com/yudai/gotty/releases/download/${GOTTY_VERSION}/gotty_linux_amd64" -O gotty; then
        echo "❌ Failed to download gotty"
        exit 1
    fi
    chmod +x gotty
    sudo mv gotty /usr/local/bin/gotty
else
    echo "gotty already installed"
fi

echo "### Updating password for default user (runner) ###"
if ! echo "runner:$LINUX_USER_PASSWORD" | sudo chpasswd; then
    echo "❌ Failed to update user password"
    exit 1
fi

echo "### Starting gotty web terminal on port $PORT ###"
if ! /usr/local/bin/gotty -w -p "$PORT" bash >/dev/null 2>&1 & then
    echo "❌ Failed to start gotty"
    exit 1
fi
sleep 2

echo "### Starting ngrok HTTP tunnel for port $PORT ###"
if ! /usr/local/bin/ngrok http --region="$NGROK_REGION" "$PORT" >ngrok.log 2>&1 & then
    echo "❌ Failed to start ngrok"
    exit 1
fi

# Wait for ngrok to initialize
NGROK_URL=""
for i in {1..15}; do
    NGROK_URL=$(curl -s http://127.0.0.1:4040/api/tunnels | grep -oE 'https://[0-9a-z-]+\.ngrok\.io' | head -n 1)
    if [[ -n "$NGROK_URL" ]]; then
        break
    fi
    sleep 2
done

if [[ -z "$NGROK_URL" ]]; then
    echo "❌ Ngrok tunnel failed to start or no URL found. Check ngrok.log for details."
    cat ngrok.log
    exit 2
fi

echo ""
echo "=========================================="
echo "🔓 Web shell available at: $NGROK_URL"
echo "Login with user: runner"
echo "Password: $LINUX_USER_PASSWORD"
echo "=========================================="
echo "Note: Keep this terminal open to maintain the tunnel"
echo "Press Ctrl+C to terminate"

# Keep script running
wait
