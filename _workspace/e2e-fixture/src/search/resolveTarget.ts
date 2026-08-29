/** 후보 중 가장 짧은 경로를 고른다 (search 규칙). */
export function resolveTarget(candidates: string[]): string | undefined {
  return [...candidates].sort((left, right) => left.length - right.length)[0];
}
