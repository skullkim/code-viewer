/** 후보 중 첫 번째를 고른다 (core 규칙). */
export function resolveTarget(candidates: string[]): string | undefined {
  return candidates[0];
}
