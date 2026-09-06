import Testing
@testable import CodeNavigatorCore

/// Reference search is name-based, so `member.getId()` lists every `getId` in the project. Measured
/// on a 463-file repository: 670 hits across 15 unrelated receiver types, of which only 339 were
/// the `Member` the user was actually looking at.
///
/// Narrowing needs one answer per hit — what type is the receiver? — and these are the shapes that
/// answer has to survive.
@Suite("Java 수신자 타입 해석")
struct JavaReceiverTypeTests {

    private func receiverType(of source: String, line: Int, symbol: String) -> String? {
        JavaReceiverType.resolve(source: source, line: line, symbolName: symbol)
    }

    @Test("지역 변수의 선언 타입을 읽는다")
    func resolvesALocalVariable() {
        let source = """
        class Sample {
            void run() {
                Member member = repository.find();
                use(member.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 4, symbol: "getId") == "Member")
    }

    @Test("메서드 파라미터의 타입을 읽는다")
    func resolvesAParameter() {
        let source = """
        class Sample {
            void run(Organization organization) {
                use(organization.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Organization")
    }

    @Test("필드의 타입을 읽는다 — 선언이 사용처보다 아래에 있어도 된다")
    func resolvesAFieldDeclaredAfterUse() {
        let source = """
        class Sample {
            void run() {
                use(coupon.getId());
            }

            private Coupon coupon;
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Coupon")
    }

    @Test("제네릭 인자는 떼고 원 타입만 남긴다")
    func stripsGenericArguments() {
        let source = """
        class Sample {
            void run() {
                Optional<Member> found = repository.find();
                use(found.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 4, symbol: "getId") == "Optional")
    }

    @Test("향상된 for 문의 변수 타입을 읽는다")
    func resolvesAForEachVariable() {
        let source = """
        class Sample {
            void run(List<Coupon> coupons) {
                for (Coupon coupon : coupons) {
                    use(coupon.getId());
                }
            }
        }
        """
        #expect(receiverType(of: source, line: 4, symbol: "getId") == "Coupon")
    }

    @Test("수신자가 없으면 그 클래스 자신이다")
    func resolvesBareCallsToTheEnclosingClass() {
        let source = """
        class Sample {
            void run() {
                use(getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Sample")
    }

    @Test("this 수신자도 그 클래스다")
    func resolvesThisToTheEnclosingClass() {
        let source = """
        class Sample {
            void run() {
                use(this.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Sample")
    }

    @Test("대문자로 시작하는 수신자는 그 타입의 정적 호출이다")
    func resolvesAStaticCall() {
        let source = """
        class Sample {
            void run() {
                use(Coupon.of(1L));
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "of") == "Coupon")
    }

    /// 같은 이름이 메서드마다 다른 타입일 수 있다. 파일 전체에서 한 번만 찾으면 다른 메서드의
    /// 선언이 새어 들어온다 — 그러면 좁히기가 오히려 틀린 답을 준다.
    @Test("같은 이름의 지역 변수가 메서드마다 다르면 그 메서드 것을 쓴다")
    func prefersTheDeclarationInTheEnclosingMethod() {
        let source = """
        class Sample {
            void first() {
                Member target = null;
                use(target.getId());
            }

            void second() {
                Coupon target = null;
                use(target.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 4, symbol: "getId") == "Member")
        #expect(receiverType(of: source, line: 9, symbol: "getId") == "Coupon")
    }

    /// 못 알아내는 경우가 있는 것은 정상이다. 중요한 건 **틀린 답 대신 모른다고 하는 것** —
    /// 모른다고 하면 그 히트는 남고, 틀린 답을 하면 진짜 참조가 사라진다.
    @Test("체인 호출의 수신자는 모른다고 답한다 — 추측하지 않는다")
    func returnsNilForAChainedReceiver() {
        let source = """
        class Sample {
            void run() {
                use(repository.find(id).getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == nil)
    }

    @Test("선언을 못 찾은 식별자는 모른다고 답한다")
    func returnsNilForAnUndeclaredIdentifier() {
        let source = """
        class Sample {
            void run() {
                use(mystery.getId());
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == nil)
    }

    /// `Coupon::getId` 는 호출이 아니라 메서드 참조라 `(` 가 뒤에 없다. 그래서 "판정 못 함"
    /// 으로 남아 있었는데, 수신자가 바로 앞에 적혀 있으므로 판정할 수 있다.
    @Test("메서드 참조의 수신자 타입도 읽는다")
    func resolvesAMethodReference() {
        let source = """
        class Sample {
            void run(List<Coupon> coupons) {
                coupons.stream().map(Coupon::getId);
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Coupon")
    }

    @Test("변수의 메서드 참조도 그 변수의 타입으로 읽는다")
    func resolvesAnInstanceMethodReference() {
        let source = """
        class Sample {
            void run(Member member) {
                supply(member::getId);
            }
        }
        """
        #expect(receiverType(of: source, line: 3, symbol: "getId") == "Member")
    }

    @Test("파싱이 깨진 파일에서도 죽지 않는다")
    func survivesBrokenSource() {
        #expect(receiverType(of: "class {{{ oops", line: 1, symbol: "getId") == nil)
        #expect(receiverType(of: "", line: 1, symbol: "getId") == nil)
        #expect(receiverType(of: "class A {}", line: 999, symbol: "getId") == nil)
    }
}
