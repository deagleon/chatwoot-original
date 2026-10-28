# frozen_string_literal: true

class Integrations::Trello::PhoneParser
  pattr_initialize [:text!]

  # Matches phone-like sequences in card text: +55 (85) 98765-4321,
  # (85) 98765-4321, 85 9 8765-4321, 85987654321, 85 98765-4321, etc.
  # Country code is optional and defaults to +55 (Brazil) when absent.
  # The trailing boundary rejects longer digit runs split by separators
  # (card numbers, IDs), which are then also filtered structurally below.
  PHONE_PATTERN = %r{(?<!\d)(?:\+?\d{2}[-\s.]?)?\(?\d{2}\)?[-\s.]?(?:9[-\s.]?)?\d{4}[-\s.]?\d{4}(?![-\s.]?\d)}

  # Valid Brazilian area codes (DDD).
  VALID_DDDS = %w[
    11 12 13 14 15 16 17 18 19 21 22 24 26 27 28 31 32 33 34 35 37 38
    41 42 43 44 45 46 47 48 49 51 53 54 55 61 62 63 64 65 66 67 68 69
    71 73 74 75 77 79 81 82 83 84 85 86 87 88 89 91 92 93 94 95 96 97 98 99
  ].freeze

  def perform
    match = text.to_s.scan(PHONE_PATTERN).first
    return if match.blank?

    normalize(match.gsub(/\D/, ''))
  end

  private

  def normalize(digits)
    digits = "55#{digits}" unless digits.length >= 12 && digits.start_with?('55')
    national = digits.delete_prefix('55')

    # Only accept structurally plausible Brazilian numbers: DDD + 8-digit
    # landline or 9-digit mobile (9-digit must start with 9). This rejects
    # CPFs, order IDs and card-number runs that pass the regex.
    return unless national.length.in?([10, 11])
    return unless VALID_DDDS.include?(national[0, 2])
    return if national.length == 11 && !national[2..].start_with?('9')

    "+55#{national}"
  end
end
