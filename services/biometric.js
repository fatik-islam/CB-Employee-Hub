export const euclideanDistance = (a, b) => {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) {
    throw new Error('Face descriptor shape mismatch');
  }

  let sum = 0;
  for (let i = 0; i < a.length; i += 1) {
    const d = Number(a[i]) - Number(b[i]);
    sum += d * d;
  }

  return Math.sqrt(sum);
};

export const isFaceMatch = ({ storedDescriptor, candidateDescriptor, threshold = 0.5 }) => {
  const distance = euclideanDistance(storedDescriptor, candidateDescriptor);

  return {
    distance,
    matched: distance <= threshold,
  };
};

export const normalizeDescriptor = (descriptor) => {
  if (!Array.isArray(descriptor)) {
    throw new Error('Invalid descriptor payload');
  }

  const normalized = descriptor.map((v) => Number(v));

  if (normalized.some((v) => Number.isNaN(v))) {
    throw new Error('Descriptor contains invalid numeric values');
  }

  return normalized;
};

export const toBase64Url = (input) =>
  Buffer.from(input)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');

export const fromBase64Url = (value) => {
  const base64 = value.replace(/-/g, '+').replace(/_/g, '/');
  const padding = (4 - (base64.length % 4)) % 4;

  return Buffer.from(base64 + '='.repeat(padding), 'base64');
};
