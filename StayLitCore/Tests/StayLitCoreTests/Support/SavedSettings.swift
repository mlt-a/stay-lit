/// What the model handed over to be stored.
@MainActor
final class SavedSettings {
    private(set) var values: [Bool] = []

    func save(_ value: Bool) { values.append(value) }
}
