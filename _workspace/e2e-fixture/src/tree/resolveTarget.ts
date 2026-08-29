/** 후보 중 마지막을 고른다 (tree 규칙). */
export function resolveTarget(candidates: string[]): string | undefined {
  return candidates[candidates.length - 1];
}
