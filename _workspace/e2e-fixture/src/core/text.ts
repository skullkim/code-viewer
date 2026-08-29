/** 한글이 섞인 줄에서 커서·셀 폭이 어긋나지 않는지 눈으로 확인하는 자리. */
export const 안내문 = '사용자Index 는 Index 검색에 걸리면 안 된다';

export function 요약하다(문장: string): string {
  return 문장.slice(0, 10) + '…';
}
