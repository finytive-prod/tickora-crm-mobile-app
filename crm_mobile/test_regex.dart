void main() {
  String clean = ".pending-1790659846-Call_7880048800_20260922_110046.m4a";
  RegExp regExp = RegExp(r"^\.?pending[-_]?[a-zA-Z0-9]*[-_]?", caseSensitive: false);
  clean = clean.replaceAll(regExp, "");
  print(clean);
}
