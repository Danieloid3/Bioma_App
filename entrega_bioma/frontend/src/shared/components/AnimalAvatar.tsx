import { Bird, Bug, PawPrint, Rabbit, Squirrel, Turtle, type LucideIcon } from "lucide-react";

const animalIcons = {
  spectacled_bear: PawPrint,
  andean_condor: Bird,
  golden_poison_frog: Bug,
  jaguar: PawPrint,
  hummingbird: Bird,
  cotton_top_tamarin: Squirrel,
  green_iguana: Turtle,
  mountain_tapir: Rabbit,
} as const satisfies Record<string, LucideIcon>;

export type AnimalAvatarKey = keyof typeof animalIcons;

const avatarKeys = Object.keys(animalIcons) as AnimalAvatarKey[];

/**
 * Resolves a curated API key when it is available. Until the API provides one,
 * the immutable researcher id gives each person a stable fauna avatar without
 * putting presentation data in the database or client storage.
 */
function resolveAnimalAvatar(key: string | null | undefined, seed: string): AnimalAvatarKey {
  const normalizedKey = key?.trim().toLowerCase();
  if (normalizedKey && normalizedKey in animalIcons) return normalizedKey as AnimalAvatarKey;

  let hash = 0;
  for (const character of seed) hash = (hash * 31 + character.charCodeAt(0)) | 0;
  return avatarKeys[Math.abs(hash) % avatarKeys.length];
}

export function AnimalAvatar({ avatarKey, seed }: { avatarKey?: string | null; seed: string }) {
  const Icon = animalIcons[resolveAnimalAvatar(avatarKey, seed)];
  return <div className="avatar" aria-hidden="true"><Icon /></div>;
}
