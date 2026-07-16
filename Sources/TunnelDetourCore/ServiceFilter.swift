import Foundation

public enum ServiceFilter {
    public static func matchingGroups(
        _ groups: [ServiceDirectGroup],
        query: String
    ) -> [ServiceDirectGroup] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return groups }

        return groups.filter { group in
            [group.id, group.name, group.category].contains { value in
                value.lowercased().localizedStandardContains(needle)
            }
        }
    }
}
