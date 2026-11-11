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

  # ISO alpha-2 code -> region name. Used by the club "Literature DNA" to talk
  # about taste in regional terms ("you've barely touched Latin America").
  def self.region_for(code)
    return nil unless /\A[A-Z]{2}\z/.match?(code.to_s)

    REGION_BY_CODE[code]
  end

  def self.build_region_map
    africa = %w[AO BF BI BJ BW CD CF CG CI CM CV DJ DZ EG EH ER ET GA GH GM GN GQ GW KE KM LR LS LY MA MG ML MR MU MW MZ NA NE NG RE RW SC SD SL SN SO SS ST SZ TD TG TN TZ UG YT ZA ZM ZW]
    europe = %w[AD AL AT AX BA BE BG BY CH CY CZ DE DK EE ES FI FO FR GB GG GI GR HR HU IE IM IS IT JE LI LT LU LV MC MD ME MK MT NL NO PL PT RS RU SE SI SK SM UA VA XK]
    asia = %w[AE AF AM AZ BD BH BN BT CN GE HK ID IL IN IQ IR JO JP KG KH KP KR KW KZ LA LB LK MM MN MO MV MY NP OM PH PK PS QA SA SG SY TH TJ TL TM TR TW UZ VN YE]
    north_america = %w[AG AI AW BB BL BM BQ BS BZ CA CR CU CW DM DO GD GL GT HN HT JM KN KY LC MF MQ MX MS NI PA PM PR SV SX TC TT US VC VG VI]
    south_america = %w[AR BO BR CL CO EC FK GF GY PE PY SR UY VE]
    oceania = %w[AS AU CK FJ FM GU KI MH MP NC NF NR NU NZ PF PG PN PW SB TF TK TO TV UM VU WF WS]

    map = {}
    africa.each { |c| map[c] = "Africa" }
    europe.each { |c| map[c] = "Europe" }
    asia.each { |c| map[c] = "Asia" }
    north_america.each { |c| map[c] = "North America" }
    south_america.each { |c| map[c] = "South America" }
    oceania.each { |c| map[c] = "Oceania" }
    map
  end
  private_class_method :build_region_map

  REGION_BY_CODE = build_region_map.freeze

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
