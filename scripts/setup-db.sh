#!/bin/bash

set -e

echo "🗄️  Setting up database..."

# Load environment variables
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

# Run Prisma migrations
echo "Running database migrations..."
cd shared && npx prisma migrate deploy && cd ..

# Seed database with sample data (optional)
echo "Would you like to seed the database with sample data? (y/n)"
read -r response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo "Seeding database..."
    node scripts/seed.js
fi

echo "✅ Database setup complete!"

# Made with Bob
