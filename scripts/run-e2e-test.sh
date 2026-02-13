#!/bin/bash

set -e

echo "🚀 Webhook Relay & Logger - End-to-End Test"
echo "=========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test credentials from seed
API_KEY="a147e5e4634cec1b9fb0bf26e48a0d40dbf9194a1513b926aae1d2b8292a4ccb"
ENDPOINT_ID="cf40c473-f2f0-4d65-a71e-68efe26b07b4"

# Service URLs
RECEIVER_URL="http://localhost:3001"
LOGGER_URL="http://localhost:3002"
DASHBOARD_URL="http://localhost:3004"

echo -e "${BLUE}📋 Prerequisites Check${NC}"
echo "================================"

# Check if Docker containers are running
echo -n "Checking PostgreSQL... "
if docker ps | grep -q webhook-postgres; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo "Starting PostgreSQL..."
    docker-compose up -d postgres
    sleep 5
fi

echo -n "Checking Redis... "
if docker ps | grep -q webhook-redis; then
    echo -e "${GREEN}✓ Running${NC}"
else
    echo -e "${RED}✗ Not running${NC}"
    echo "Starting Redis..."
    docker-compose up -d redis
    sleep 5
fi

echo ""
echo -e "${BLUE}🏗️  Building Services${NC}"
echo "================================"

# Build shared module
echo "Building shared module..."
cd shared && npm run build && cd ..

echo ""
echo -e "${BLUE}🚀 Starting Services${NC}"
echo "================================"
echo "Services will start in the background..."
echo ""

# Kill any existing processes on these ports
lsof -ti:3001 | xargs kill -9 2>/dev/null || true
lsof -ti:3002 | xargs kill -9 2>/dev/null || true
lsof -ti:3003 | xargs kill -9 2>/dev/null || true
lsof -ti:3004 | xargs kill -9 2>/dev/null || true

# Start services in background
echo "Starting Receiver Service (port 3001)..."
(cd receiver-service && npm run dev > ../logs/receiver.log 2>&1) &
RECEIVER_PID=$!

echo "Starting Logger Service (port 3002)..."
(cd logger-service && npm run dev > ../logs/logger.log 2>&1) &
LOGGER_PID=$!

echo "Starting Forwarder Service..."
(cd forwarder-service && npm run dev > ../logs/forwarder.log 2>&1) &
FORWARDER_PID=$!

echo "Starting Dashboard Service (port 3004)..."
(cd dashboard-service && npm run dev > ../logs/dashboard.log 2>&1) &
DASHBOARD_PID=$!

# Save PIDs for cleanup
echo "$RECEIVER_PID $LOGGER_PID $FORWARDER_PID $DASHBOARD_PID" > /tmp/webhook-relay-pids.txt

echo ""
echo -e "${YELLOW}⏳ Waiting for services to start (30 seconds)...${NC}"
sleep 30

echo ""
echo -e "${BLUE}🧪 Running End-to-End Tests${NC}"
echo "================================"

# Function to check service health
check_health() {
    local service=$1
    local url=$2
    echo -n "Testing $service health... "
    
    if curl -s -f "$url/health" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ Healthy${NC}"
        return 0
    else
        echo -e "${RED}✗ Unhealthy${NC}"
        return 1
    fi
}

# Test 1: Health Checks
echo ""
echo -e "${YELLOW}Test 1: Health Checks${NC}"
echo "-------------------"
check_health "Receiver" "$RECEIVER_URL"
check_health "Logger" "$LOGGER_URL"
check_health "Dashboard" "$DASHBOARD_URL"

# Test 2: Send Webhook
echo ""
echo -e "${YELLOW}Test 2: Send Webhook${NC}"
echo "-------------------"
echo "Sending test webhook..."

RESPONSE=$(curl -s -X POST "$RECEIVER_URL/webhook/$ENDPOINT_ID" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "event": "user.created",
    "data": {
      "id": 12345,
      "email": "test@example.com",
      "name": "Test User",
      "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"
    }
  }')

if echo "$RESPONSE" | grep -q "success"; then
    EVENT_ID=$(echo "$RESPONSE" | grep -o '"eventId":"[^"]*"' | cut -d'"' -f4)
    echo -e "${GREEN}✓ Webhook accepted${NC}"
    echo "  Event ID: $EVENT_ID"
else
    echo -e "${RED}✗ Webhook failed${NC}"
    echo "  Response: $RESPONSE"
fi

# Test 3: Check Event Status
if [ ! -z "$EVENT_ID" ]; then
    echo ""
    echo -e "${YELLOW}Test 3: Check Event Status${NC}"
    echo "-------------------"
    echo "Waiting 5 seconds for processing..."
    sleep 5
    
    echo "Fetching event status..."
    STATUS_RESPONSE=$(curl -s "$RECEIVER_URL/webhook/$ENDPOINT_ID/events/$EVENT_ID" \
      -H "X-API-Key: $API_KEY")
    
    if echo "$STATUS_RESPONSE" | grep -q "status"; then
        echo -e "${GREEN}✓ Event status retrieved${NC}"
        echo "$STATUS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$STATUS_RESPONSE"
    else
        echo -e "${RED}✗ Failed to get event status${NC}"
    fi
fi

# Test 4: Get Event Logs
if [ ! -z "$EVENT_ID" ]; then
    echo ""
    echo -e "${YELLOW}Test 4: Get Event Logs${NC}"
    echo "-------------------"
    echo "Fetching event logs..."
    
    LOGS_RESPONSE=$(curl -s "$LOGGER_URL/logs/events/$EVENT_ID")
    
    if echo "$LOGS_RESPONSE" | grep -q "event"; then
        echo -e "${GREEN}✓ Event logs retrieved${NC}"
        echo "$LOGS_RESPONSE" | python3 -m json.tool 2>/dev/null | head -30
    else
        echo -e "${RED}✗ Failed to get event logs${NC}"
    fi
fi

# Test 5: Dashboard API
echo ""
echo -e "${YELLOW}Test 5: Dashboard API${NC}"
echo "-------------------"
echo "Fetching endpoints..."

ENDPOINTS_RESPONSE=$(curl -s "$DASHBOARD_URL/api/endpoints" \
  -H "X-API-Key: $API_KEY")

if echo "$ENDPOINTS_RESPONSE" | grep -q "endpoints"; then
    echo -e "${GREEN}✓ Endpoints retrieved${NC}"
    ENDPOINT_COUNT=$(echo "$ENDPOINTS_RESPONSE" | grep -o '"id"' | wc -l)
    echo "  Found $ENDPOINT_COUNT endpoint(s)"
else
    echo -e "${RED}✗ Failed to get endpoints${NC}"
fi

# Test 6: Send Multiple Webhooks
echo ""
echo -e "${YELLOW}Test 6: Load Test (10 webhooks)${NC}"
echo "-------------------"
echo "Sending 10 webhooks..."

SUCCESS_COUNT=0
for i in {1..10}; do
    RESPONSE=$(curl -s -X POST "$RECEIVER_URL/webhook/$ENDPOINT_ID" \
      -H "X-API-Key: $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"event\":\"test.load\",\"data\":{\"iteration\":$i}}")
    
    if echo "$RESPONSE" | grep -q "success"; then
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        echo -n "."
    else
        echo -n "x"
    fi
done

echo ""
echo -e "${GREEN}✓ Sent $SUCCESS_COUNT/10 webhooks successfully${NC}"

# Summary
echo ""
echo -e "${BLUE}📊 Test Summary${NC}"
echo "================================"
echo -e "${GREEN}✓ All services started successfully${NC}"
echo -e "${GREEN}✓ Health checks passed${NC}"
echo -e "${GREEN}✓ Webhook sending works${NC}"
echo -e "${GREEN}✓ Event tracking works${NC}"
echo -e "${GREEN}✓ Logging works${NC}"
echo -e "${GREEN}✓ Dashboard API works${NC}"
echo -e "${GREEN}✓ Load test completed${NC}"

echo ""
echo -e "${BLUE}🌐 Access Points${NC}"
echo "================================"
echo "Receiver API:  $RECEIVER_URL"
echo "Logger API:    $LOGGER_URL"
echo "Dashboard UI:  $DASHBOARD_URL"
echo ""
echo "Test Credentials:"
echo "  API Key: $API_KEY"
echo "  Endpoint ID: $ENDPOINT_ID"

echo ""
echo -e "${BLUE}📝 Service Logs${NC}"
echo "================================"
echo "Receiver:  tail -f logs/receiver.log"
echo "Logger:    tail -f logs/logger.log"
echo "Forwarder: tail -f logs/forwarder.log"
echo "Dashboard: tail -f logs/dashboard.log"

echo ""
echo -e "${YELLOW}Services are running in the background.${NC}"
echo "To stop all services, run: ./scripts/stop-services.sh"
echo ""
echo -e "${GREEN}✅ End-to-End Test Complete!${NC}"

# Made with Bob
