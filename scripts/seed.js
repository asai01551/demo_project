const { PrismaClient } = require('@prisma/client');
const crypto = require('crypto');

const prisma = new PrismaClient();

function generateApiKey() {
  return crypto.randomBytes(32).toString('hex');
}

async function seed() {
  console.log('🌱 Seeding database...');

  // Create sample user
  const user = await prisma.user.create({
    data: {
      email: 'demo@example.com',
      apiKey: generateApiKey(),
    },
  });

  console.log(`✅ Created user: ${user.email}`);
  console.log(`🔑 API Key: ${user.apiKey}`);

  // Create sample endpoints
  const endpoint1 = await prisma.endpoint.create({
    data: {
      userId: user.id,
      name: 'Production Webhook',
      destinationUrl: 'https://example.com/webhook',
      isActive: true,
    },
  });

  const endpoint2 = await prisma.endpoint.create({
    data: {
      userId: user.id,
      name: 'Staging Webhook',
      destinationUrl: 'https://staging.example.com/webhook',
      isActive: true,
    },
  });

  console.log(`✅ Created endpoints: ${endpoint1.name}, ${endpoint2.name}`);

  // Create sample stats
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  await prisma.endpointStats.create({
    data: {
      endpointId: endpoint1.id,
      date: today,
      totalReceived: 150,
      totalDelivered: 145,
      totalFailed: 5,
      avgResponseTime: 250,
    },
  });

  console.log('✅ Created sample statistics');
  console.log('\n📝 Save this API key for testing:');
  console.log(`   ${user.apiKey}`);
  console.log('\n🎯 Webhook endpoint IDs:');
  console.log(`   ${endpoint1.id} - ${endpoint1.name}`);
  console.log(`   ${endpoint2.id} - ${endpoint2.name}`);
}

seed()
  .catch((e) => {
    console.error('Error seeding database:', e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });

// Made with Bob
