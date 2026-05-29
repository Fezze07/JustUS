class Validators {
  static String? validateEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'L\'email è obbligatoria';
    }
    final emailRegExp = RegExp(
      r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+",
    );
    if (!emailRegExp.hasMatch(email.trim())) {
      return 'Inserisci un\'email valida';
    }

    return null;
  }

  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'La password è obbligatoria';
    }
    if (password.length < 8) {
      return 'La password deve avere almeno 8 caratteri';
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      return 'Deve contenere almeno una minuscola';
    }
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      return 'Deve contenere almeno una maiuscola';
    }
    if (!RegExp(r'[0-9]').hasMatch(password)) {
      return 'Deve contenere almeno un numero';
    }
    if (!RegExp(r'[!@#\$%^&*(),.?":{}|<>]').hasMatch(password)) {
      return 'Deve contenere almeno un simbolo';
    }

    return null;
  }

  static String? validateRequired(String? value, String fieldName) {
    if (value == null || value.trim().isEmpty) {
      return 'Il campo $fieldName è obbligatorio';
    }

    return null;
  }
}
