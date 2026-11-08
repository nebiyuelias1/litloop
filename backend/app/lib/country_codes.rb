# frozen_string_literal: true

# ISO 3166-1 alpha-2 country codes used by AI book enrichment and display.
#
# The model outputs official English country names; this module converts them
# to codes and validates them before they can reach the database.
module CountryCodes
  NAMES_TO_CODES = {
    "Afghanistan" => "AF", "Albania" => "AL", "Algeria" => "DZ", "Andorra" => "AD",
    "Angola" => "AO", "Antigua and Barbuda" => "AG", "Argentina" => "AR", "Armenia" => "AM",
    "Australia" => "AU", "Austria" => "AT", "Azerbaijan" => "AZ", "Bahamas" => "BS",
    "Bahrain" => "BH", "Bangladesh" => "BD", "Barbados" => "BB", "Belarus" => "BY",
    "Belgium" => "BE", "Belize" => "BZ", "Benin" => "BJ", "Bhutan" => "BT",
    "Bolivia" => "BO", "Bosnia and Herzegovina" => "BA", "Botswana" => "BW", "Brazil" => "BR",
    "Brunei" => "BN", "Bulgaria" => "BG", "Burkina Faso" => "BF", "Burundi" => "BI",
    "Cabo Verde" => "CV", "Cape Verde" => "CV", "Cambodia" => "KH", "Cameroon" => "CM",
    "Canada" => "CA", "Central African Republic" => "CF", "Chad" => "TD", "Chile" => "CL",
    "China" => "CN", "Colombia" => "CO", "Comoros" => "KM", "Congo" => "CG",
    "Republic of the Congo" => "CG", "Democratic Republic of the Congo" => "CD",
    "DR Congo" => "CD", "Costa Rica" => "CR", "Croatia" => "HR", "Cuba" => "CU",
    "Cyprus" => "CY", "Czechia" => "CZ", "Czech Republic" => "CZ", "Denmark" => "DK",
    "Djibouti" => "DJ", "Dominica" => "DM", "Dominican Republic" => "DO", "Ecuador" => "EC",
    "Egypt" => "EG", "El Salvador" => "SV", "Equatorial Guinea" => "GQ", "Eritrea" => "ER",
    "Estonia" => "EE", "Eswatini" => "SZ", "Swaziland" => "SZ", "Ethiopia" => "ET",
    "Fiji" => "FJ", "Finland" => "FI", "France" => "FR", "Gabon" => "GA",
    "Gambia" => "GM", "Georgia" => "GE", "Germany" => "DE", "Ghana" => "GH",
    "Greece" => "GR", "Grenada" => "GD", "Guatemala" => "GT", "Guinea" => "GN",
    "Guinea-Bissau" => "GW", "Guyana" => "GY", "Haiti" => "HT", "Honduras" => "HN",
    "Hungary" => "HU", "Iceland" => "IS", "India" => "IN", "Indonesia" => "ID",
    "Iran" => "IR", "Iraq" => "IQ", "Ireland" => "IE", "Israel" => "IL",
    "Italy" => "IT", "Ivory Coast" => "CI", "Cote d'Ivoire" => "CI", "Jamaica" => "JM",
    "Japan" => "JP", "Jordan" => "JO", "Kazakhstan" => "KZ", "Kenya" => "KE",
    "Kiribati" => "KI", "Kosovo" => "XK", "Kuwait" => "KW", "Kyrgyzstan" => "KG",
    "Laos" => "LA", "Latvia" => "LV", "Lebanon" => "LB", "Lesotho" => "LS",
    "Liberia" => "LR", "Libya" => "LY", "Liechtenstein" => "LI", "Lithuania" => "LT",
    "Luxembourg" => "LU", "Madagascar" => "MG", "Malawi" => "MW", "Malaysia" => "MY",
    "Maldives" => "MV", "Mali" => "ML", "Malta" => "MT", "Marshall Islands" => "MH",
    "Mauritania" => "MR", "Mauritius" => "MU", "Mexico" => "MX", "Micronesia" => "FM",
    "Moldova" => "MD", "Monaco" => "MC", "Mongolia" => "MN", "Montenegro" => "ME",
    "Morocco" => "MA", "Mozambique" => "MZ", "Myanmar" => "MM", "Burma" => "MM",
    "Namibia" => "NA", "Nauru" => "NR", "Nepal" => "NP", "Netherlands" => "NL",
    "Holland" => "NL", "New Zealand" => "NZ", "Nicaragua" => "NI", "Niger" => "NE",
    "Nigeria" => "NG", "North Korea" => "KP", "North Macedonia" => "MK",
    "Norway" => "NO", "Oman" => "OM", "Pakistan" => "PK", "Palau" => "PW",
    "Palestine" => "PS", "Panama" => "PA", "Papua New Guinea" => "PG", "Paraguay" => "PY",
    "Peru" => "PE", "Philippines" => "PH", "Poland" => "PL", "Portugal" => "PT",
    "Qatar" => "QA", "Romania" => "RO", "Russia" => "RU", "Rwanda" => "RW",
    "Samoa" => "WS", "San Marino" => "SM", "Sao Tome and Principe" => "ST",
    "Saudi Arabia" => "SA", "Senegal" => "SN", "Serbia" => "RS", "Seychelles" => "SC",
    "Sierra Leone" => "SL", "Singapore" => "SG", "Slovakia" => "SK", "Slovenia" => "SI",
    "Solomon Islands" => "SB", "Somalia" => "SO", "South Africa" => "ZA",
    "South Korea" => "KR", "Sudan" => "SD", "South Sudan" => "SS",
    "Spain" => "ES", "Sri Lanka" => "LK", "Suriname" => "SR", "Sweden" => "SE",
    "Switzerland" => "CH", "Syria" => "SY", "Taiwan" => "TW", "Tajikistan" => "TJ",
    "Tanzania" => "TZ", "Thailand" => "TH", "Timor-Leste" => "TL", "East Timor" => "TL",
    "Togo" => "TG", "Tonga" => "TO", "Trinidad and Tobago" => "TT", "Tunisia" => "TN",
    "Turkey" => "TR", "Turkmenistan" => "TM", "Tuvalu" => "TV", "Uganda" => "UG",
    "Ukraine" => "UA", "United Arab Emirates" => "AE", "United Kingdom" => "GB", "UK" => "GB",
    "United States" => "US", "United States of America" => "US", "USA" => "US", "US" => "US", "Uruguay" => "UY", "Uzbekistan" => "UZ", "Vanuatu" => "VU",
    "Venezuela" => "VE", "Vietnam" => "VN", "Yemen" => "YE", "Zambia" => "ZM",
    "Zimbabwe" => "ZW", "Hong Kong" => "HK", "Macao" => "MO"
  }.freeze

  CODES = NAMES_TO_CODES.values.uniq.freeze

  # Official English name -> ISO 3166-1 alpha-2 code, nil when not a real country
  def self.code_for(name)
    NAMES_TO_CODES[name.to_s.strip]
  end

  # ISO alpha-2 code -> official English name, nil for unknown codes
  def self.name_for(code)
    return nil unless /\A[A-Z]{2}\z/.match?(code.to_s)

    NAMES_TO_CODES.key(code)
  end

  # ISO alpha-2 code -> flag emoji, nil for unknown codes
  def self.flag_for(code)
    return nil unless /\A[A-Z]{2}\z/.match?(code.to_s)

    code.chars.map { |letter| [ letter.ord + 127_397 ].pack("U") }.join
  end
end
