/// In-memory state remembered while the app runs (Section Step 2 & 4)
class SettingsState {
  static final Map<String, bool> _expandedGroups = {};

  static bool isExpanded(String groupId) => _expandedGroups[groupId] ?? false;

  static void setExpanded(String groupId, bool expanded) {
    _expandedGroups[groupId] = expanded;
  }

  static void toggleExpanded(String groupId) {
    _expandedGroups[groupId] = !isExpanded(groupId);
  }
}
