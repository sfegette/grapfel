import XCTest
@testable import grapfel

@MainActor
final class ChatViewModelTests: XCTestCase {

    func test_initialState() {
        let vm = ChatViewModel()
        XCTAssertEqual(vm.prompt, "")
        XCTAssertTrue(vm.history.isEmpty)
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.attachedFiles.isEmpty)
        XCTAssertEqual(vm.options, .defaults)
    }

    func test_send_withEmptyPrompt_doesNothing() async {
        let vm = ChatViewModel()
        vm.prompt = "   "
        await vm.send()
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.history.isEmpty)
    }

    func test_send_setsLoadingAndClearsPrompt() async {
        let vm = ChatViewModel()
        vm.prompt = "hello"
        await vm.send()
        // After send completes (server error expected in test environment):
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.prompt, "")
        XCTAssertFalse(vm.history.isEmpty)
    }
}
