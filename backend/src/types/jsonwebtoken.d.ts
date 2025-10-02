// Minimal declaration to satisfy TypeScript when building inside Docker
// without adding @types/jsonwebtoken to devDependencies (avoids npm ci lock churn).
declare module 'jsonwebtoken';

