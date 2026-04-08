import XCTest
@testable import grapfel

@MainActor
final class ChatViewModelTests: XCTestCase {

    func test_initialState() {
        let vm = ChatViewModel()
        XCTAssertEqual(vm.prompt, "")
        XCTAssertEqual(vm.response, "")
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.attachedFiles.isEmpty)
        XCTAssertEqual(vm.options, .defaults)
    }

    func test_send_withEmptyPrompt_doesNothing() async {
        let vm = ChatViewModel()
        vm.prompt = "   "
        await vm.send()
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.response, "")
    }

    func test_send_setsLoadingAndClearsPrompt() async {
        let vm = ChatViewModel()
        vm.prompt = "hello"
        await vm.send()
        // After stub send completes:
        XCTAssertFalse(vm.isLoading)
        XCTAssertEqual(vm.prompt, "")
        XCTAssertFalse(vm.response.isEmpty)
    }
}
