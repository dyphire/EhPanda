import Testing
import AppModels

struct CookieValueTests {
    @Test
    func statusIconReflectsCookieState() {
        let valid = CookieValue(rawValue: "token", localizedString: "")
        let missing = CookieValue(rawValue: "", localizedString: "None")
        let expired = CookieValue(rawValue: "", localizedString: "Expired")
        let mystery = CookieValue(rawValue: "mystery", localizedString: "mystery")

        #expect(valid.isInvalid == false)
        #expect(missing.isInvalid)
        #expect(expired.isInvalid)
        #expect(mystery.isInvalid)
        #expect(missing.placeholder == "None")
        #expect(expired.placeholder == "Expired")
    }
}
