#!/bin/bash

echo "🛑 Stopping Webhook Relay Services"
echo "=================================="

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

# Read PIDs if they exist
if [ -f /tmp/webhook-relay-pids.txt ]; then
    PIDS=$(cat /tmp/webhook-relay-pids.txt)
    echo "Stopping services (PIDs: $PIDS)..."
    
    for PID in $PIDS; do
        if kill -0 $PID 2>/dev/null; then
            kill $PID 2>/dev/null
            echo -e "${GREEN}✓ Stopped process $PID${NC}"
        fi
    done
    
    rm /tmp/webhook-relay-pids.txt
else
    echo "No PID file found, killing by port..."
    
    # Kill processes on specific ports
    for PORT in 3001 3002 3003 3004; do
        PID=$(lsof -ti:$PORT 2>/dev/null)
        if [ ! -z "$PID" ]; then
            kill -9 $PID 2>/dev/null
            echo -e "${GREEN}✓ Stopped service on port $PORT${NC}"
        fi
    done
fi

echo ""
echo -e "${GREEN}✅ All services stopped${NC}"

# Made with Bob
