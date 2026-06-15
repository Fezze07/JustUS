class AppDateUtils {
  static int daysBetween(DateTime from, DateTime to) {
    from = DateTime(from.year, from.month, from.day);
    to = DateTime(to.year, to.month, to.day);

    return to.difference(from).inDays;
  }

  static int daysSince(DateTime date) {
    return daysBetween(date, DateTime.now());
  }

  static DateTime? tryParse(String? dateString) {
    if (dateString == null || dateString.isEmpty) return null;

    return DateTime.tryParse(dateString);
  }

  static String formatToYMD(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }
}
