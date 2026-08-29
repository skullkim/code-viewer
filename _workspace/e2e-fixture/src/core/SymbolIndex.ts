import { resolveTarget } from './resolveTarget';

/** 심볼 이름으로 정의 위치를 찾는 색인. */
export class SymbolIndex {
  private readonly entries = new Map<string, string[]>();

  add(name: string, path: string): void {
    const existing = this.entries.get(name) ?? [];
    existing.push(path);
    this.entries.set(name, existing);
  }

  find(name: string): string[] {
    return this.entries.get(name) ?? [];
  }

  locate(name: string): string | undefined {
    return resolveTarget(this.find(name));
  }
}

/** 이름이 겹치는 다른 타입 — SymbolIndex 검색에 섞이면 안 된다. */
export class SymbolIndexHolder {
  constructor(readonly index: SymbolIndex) {}
}
