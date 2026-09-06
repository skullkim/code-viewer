import Testing
import CodeNavigatorContract

/// 브레이크포인트는 파일 경로가 아니라 **클래스 이름**으로 건다. JDWP 는 파일을 모른다 —
/// `Lcom/example/Probe;` 같은 시그니처만 안다. 그 사이를 잇는 것이 이 변환이고, 틀리면
/// 브레이크포인트가 "그런 클래스 없음" 으로 조용히 실패한다.
@Suite("Java 클래스 이름 — 파일에서 FQN 으로")
struct JavaTypeNameTests {

    @Test("package 선언과 파일 이름을 합친다")
    func joinsThePackageAndTheFileName() {
        let source = """
        package com.woowacourse.thankoo.member.domain;

        public class Member {
        }
        """
        #expect(
            JavaTypeName.forSource(source, fileName: "Member.java")
                == "com.woowacourse.thankoo.member.domain.Member"
        )
    }

    @Test("기본 패키지면 파일 이름만이다")
    func handlesTheDefaultPackage() {
        #expect(JavaTypeName.forSource("public class Probe {}", fileName: "Probe.java") == "Probe")
    }

    /// `package` 는 주석 뒤에 올 수도 있고 앞에 라이선스 헤더가 붙기도 한다.
    @Test("라이선스 헤더 뒤의 package 도 찾는다")
    func findsThePackageAfterAHeaderComment() {
        let source = """
        /*
         * Copyright 2026.
         */
        package com.example.deep;

        class Thing {}
        """
        #expect(JavaTypeName.forSource(source, fileName: "Thing.java") == "com.example.deep.Thing")
    }

    /// 문자열이나 주석 안의 `package` 를 선언으로 읽으면 엉뚱한 패키지가 나온다.
    @Test("주석 안의 package 라는 낱말에 속지 않는다")
    func ignoresThePackageWordInAComment() {
        let source = """
        // this package is about members
        package com.real.one;

        class Thing {}
        """
        #expect(JavaTypeName.forSource(source, fileName: "Thing.java") == "com.real.one.Thing")
    }

    @Test("경로에서도 만들 수 있다")
    func buildsFromAPath() {
        let source = "package com.example;\nclass Widget {}"
        #expect(
            JavaTypeName.forFile(atPath: "src/main/java/com/example/Widget.java", source: source)
                == "com.example.Widget"
        )
    }

    /// Java 가 아닌 파일에 브레이크포인트를 걸어 달라는 요청은 여기서 멈춰야 한다. nil 을
    /// 안 돌려주면 위층이 말도 안 되는 클래스 이름으로 JVM 에 묻는다.
    @Test("Java 가 아니면 nil 이다")
    func refusesANonJavaFile() {
        #expect(JavaTypeName.forFile(atPath: "notes.md", source: "package x;") == nil)
        #expect(JavaTypeName.forFile(atPath: "Main.kt", source: "package x") == nil)
    }
}
