/// Canonical attempt-note shortcuts stored as these exact strings.
const kUnsuccessfulNotePhrases = <String>[
  'Knocked on door, no noise or movement inside.',
  'Heard noise inside, no answer or response at the door.',
  'No vehicle on the driveway.',
  'No lights on inside the home.',
  'Lights on inside the home, no noise or movement.',
  'Secured community, requires key fob to enter.',
  'Secured building, requires key fob to enter.',
  'Waited at entrance for a few minutes.',
  'Nobody walked in or out to allow me inside.',
  'Called out for delivery no answer or response.',
];

class SubjectDescription {
  String gender = '';
  String ethnicity = '';
  String age = '';
  String height = '';
  String weight = '';
  String hairColor = '';
  bool tattoosPiercing = false;

  bool get isEmpty =>
      gender.isEmpty &&
      ethnicity.isEmpty &&
      age.isEmpty &&
      height.isEmpty &&
      weight.isEmpty &&
      hairColor.isEmpty &&
      !tattoosPiercing;

  String toNoteBlock() {
    final lines = <String>[
      if (gender.isNotEmpty) 'Gender: $gender',
      if (ethnicity.isNotEmpty) 'Ethnicity: $ethnicity',
      if (age.isNotEmpty) 'Age: $age',
      if (height.isNotEmpty) 'Height: $height',
      if (weight.isNotEmpty) 'Weight: $weight',
      if (hairColor.isNotEmpty) 'Hair Color: $hairColor',
      'Tattoos/Piercing: ${tattoosPiercing ? 'Yes' : 'No'}',
    ];
    return lines.join('\n');
  }
}
