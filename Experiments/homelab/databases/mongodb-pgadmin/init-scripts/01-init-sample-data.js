// MongoDB initialization script - runs on first startup
// Creates demo database with sample collections

print("Initializing MongoDB with sample data...");

var homelab = db.getSiblingDB("homelab");

homelab.users.insertMany([
  { name: "Alice", role: "admin", email: "alice@homelab.com" },
  { name: "Bob", role: "user", email: "bob@homelab.com" },
  { name: "Charlie", role: "user", email: "charlie@homelab.com" }
]);

homelab.products.insertMany([
  { name: "Laptop", price: 999.99, category: "electronics" },
  { name: "Keyboard", price: 79.99, category: "electronics" },
  { name: "Notebook", price: 4.99, category: "office" },
  { name: "Pen", price: 1.99, category: "office" }
]);

homelab.metrics.insertMany([
  { metric: "cpu_usage", value: 45.2, timestamp: new Date() },
  { metric: "memory_usage", value: 62.1, timestamp: new Date() },
  { metric: "disk_io", value: 12.8, timestamp: new Date() }
]);

homelab.createCollection("sessions");
homelab.sessions.createIndex({ expiresAt: 1 }, { expireAfterSeconds: 0 });

homelab.sessions.insertOne({
  userId: ObjectId(),
  token: "demo-session-token-001",
  expiresAt: new Date(Date.now() + 3600000)
});

print("Sample data inserted:");
print("  - homelab.users: " + homelab.users.countDocuments() + " documents");
print("  - homelab.products: " + homelab.products.countDocuments() + " documents");
print("  - homelab.metrics: " + homelab.metrics.countDocuments() + " documents");
print("  - homelab.sessions: created with TTL index");
print("MongoDB initialization complete.");
