enum LilyAppearance {
  kids('Kids'),
  gaming('Gaming');

  const LilyAppearance(this.label);
  final String label;

  static LilyAppearance? fromKey(String? key) {
    for (final appearance in values) {
      if (appearance.name == key) return appearance;
    }
    return null;
  }
}
