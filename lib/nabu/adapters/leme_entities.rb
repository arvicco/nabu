# frozen_string_literal: true

module Nabu
  module Adapters
    # LEME's character-entity set, snapshotted so the leme-xml parser never
    # depends on a file's own DOCTYPE and never loads a DTD. Source: the
    # internal subset of the LEME TSpace XML — 260 <!ENTITY name "value">
    # declarations, identical in every one of the 309 files that declare
    # them well-formed (census 2026-11-05 over all 314; copied verbatim from
    # 1807/102611's subset). Four files carry the subset with every value
    # lost (`<!ENTITY AElig ">`, which XML reads as one value swallowing the
    # next declaration) and one carries no DOCTYPE at all; both read through
    # this table. Values are the declarations' own text — numeric character
    # references (two of them C1 code points as LEME declares them: bullet
    # &#149;, highcaret &#136;) — decoded by the XML parser; none references
    # another entity.
    # rubocop:disable Metrics/CollectionLiteralLength -- a pinned upstream snapshot inside the parser's
    # code closure (its digest re-derives the shelves when it changes), never config data
    LEME_ENTITIES = {
      "AElig" => "&#198;", "AEligmacron" => "&#482;", "Aacute" => "&#193;", "Abreve" => "&#258;",
      "Acirc" => "&#194;", "Agrave" => "&#192;", "Alpha" => "&#913;", "Amacron" => "&#256;", "Aring" => "&#197;",
      "Atilde" => "&#195;", "Auml" => "&#196;", "Beta" => "&#914;", "Ccedil" => "&#199;", "Chi" => "&#935;",
      "Dagger" => "&#8225;", "Delta" => "&#916;", "ETH" => "&#208;", "Eacute" => "&#201;", "Ebreve" => "&#276;",
      "Ecedil" => "&#280;", "Ecirc" => "&#202;", "Egrave" => "&#200;", "Emacron" => "&#274;", "Epsilon" => "&#917;",
      "Eta" => "&#919;", "Euml" => "&#203;", "Gamma" => "&#915;", "Iacute" => "&#205;", "Ibreve" => "&#300;",
      "Icirc" => "&#206;", "Igrave" => "&#204;", "Imacron" => "&#298;", "Iota" => "&#921;", "Iuml" => "&#207;",
      "Kappa" => "&#922;", "Lambda" => "&#923;", "Mtilde" => "M&#771;", "Mu" => "&#924;", "Ntilde" => "&#209;",
      "Nu" => "&#925;", "OElig" => "&#338;", "OEligmacron" => "&#338;&#772;", "Oacute" => "&#211;",
      "Obreve" => "&#334;", "Ocirc" => "&#212;", "Ograve" => "&#210;", "Omacron" => "&#332;", "Omega" => "&#937;",
      "Omicron" => "&#927;", "Oslash" => "&#216;", "Otilde" => "&#213;", "Ouml" => "&#214;", "Phi" => "&#934;",
      "Pi" => "&#928;", "Prime" => "&#8243;", "Psi" => "&#936;", "Rho" => "&#929;", "Rx" => "&#8478;",
      "Scaron" => "&#352;", "Sigma" => "&#931;", "Stigma" => "&#x03DA;", "THORN" => "&#222;", "Tau" => "&#932;",
      "Theta" => "&#920;", "Uacute" => "&#218;", "Ubreve" => "&#364;", "Ucirc" => "&#219;", "Ugrave" => "&#217;",
      "Umacron" => "&#362;", "Upsilon" => "&#933;", "Uuml" => "&#220;", "Vacute" => "V&#769;", "WYN" => "&#503;",
      "Xi" => "&#926;", "YOGH" => "&#439;", "Yacute" => "&#221;", "Ycirc" => "&#374;", "Ygrave" => "&#7922;",
      "Ymacron" => "&#562;", "Yuml" => "&#376;", "Zeta" => "&#918;", "aacute" => "&#225;", "abreve" => "&#259;",
      "acirc" => "&#226;", "acute" => "&#180;", "aelig" => "&#230;", "aeligmacron" => "&#483;",
      "agrave" => "&#224;", "alpha" => "&#945;", "amacron" => "&#257;", "aring" => "&#229;", "arrow" => "&#8594;",
      "atilde" => "&#227;", "auml" => "&#228;", "bdquo" => "&#8222;", "beta" => "&#946;", "brvbar" => "&#166;",
      "bull" => "&#8226;", "bullet" => "&#149;", "ccedil" => "&#231;", "ccirc" => "&#265;", "cedil" => "&#184;",
      "cent" => "&#162;", "chi" => "&#967;", "circ" => "&#710;", "clubs" => "&#9827;", "copy" => "&#169;",
      "crarr" => "&#8629;", "curren" => "&#164;", "dagger" => "&#8224;", "darr" => "&#8595;", "deg" => "&#176;",
      "delta" => "&#948;", "diams" => "&#9830;", "divide" => "&#247;", "dmacron" => "&#273;", "dram" => "&#658;",
      "eacute" => "&#233;", "ebreve" => "&#277;", "ecedil" => "&#281;", "ecirc" => "&#234;", "egrave" => "&#232;",
      "emacron" => "&#275;", "emsp" => "&#8195;", "ensp" => "&#8194;", "epsilon" => "&#949;",
      "epsilontilde" => "&#949;&#834;", "eta" => "&#951;", "eth" => "&#240;", "euml" => "&#235;",
      "euro" => "&#8364;", "fist" => "&#9758;", "fnof" => "&#402;", "frac12" => "&#189;", "frac14" => "&#188;",
      "frac34" => "&#190;", "gamma" => "&#947;", "grave" => "&#96;", "harr" => "&#8596;", "hearts" => "&#9829;",
      "hellip" => "&#8230;", "highcaret" => "&#136;", "iacute" => "&#237;", "ibreve" => "&#301;",
      "icirc" => "&#238;", "iexcl" => "&#161;", "igrave" => "&#236;", "imacron" => "&#299;", "infin" => "&#8734;",
      "iota" => "&#953;", "iquest" => "&#191;", "iuml" => "&#239;", "kappa" => "&#954;", "lambda" => "&#955;",
      "laquo" => "&#171;", "larr" => "&#8592;", "lceil" => "&#8968;", "ldquo" => "&#8220;", "leaf" => "&#10087;",
      "lfloor" => "&#8970;", "longs" => "&#383;", "loz" => "&#9674;", "lrm" => "&#8206;", "lsaquo" => "&#8249;",
      "lsquo" => "&#8216;", "macr" => "&#175;", "mdash" => "&#8212;", "micro" => "&#181;", "middot" => "&#183;",
      "mtilde" => "m&#771;", "mu" => "&#956;", "nbsp" => "&#160;", "ndash" => "&#8211;", "not" => "&#172;",
      "ntilde" => "&#241;", "nu" => "&#957;", "oacute" => "&#243;", "obreve" => "&#335;", "ocirc" => "&#244;",
      "oelig" => "&#339;", "oeligmacron" => "&#339;&#772;", "ograve" => "&#242;", "oline" => "&#8254;",
      "omacron" => "&#333;", "omega" => "&#969;", "omicron" => "&#959;", "ordf" => "&#170;", "ordm" => "&#186;",
      "oslash" => "&#248;", "otilde" => "&#245;", "ouml" => "&#246;", "ounce" => "&#8485;", "para" => "&#182;",
      "permil" => "&#8240;", "phi" => "&#966;", "pi" => "&#960;", "piv" => "&#982;", "plusmn" => "&#177;",
      "pound" => "&#163;", "prime" => "&#8242;", "psi" => "&#968;", "qacute" => "q&#769;", "radic" => "&#8730;",
      "raquo" => "&#187;", "rarr" => "&#8594;", "rceil" => "&#8969;", "rdquo" => "&#8221;", "reg" => "&#174;",
      "rfloor" => "&#8971;", "rho" => "&#961;", "rlm" => "&#8207;", "rsaquo" => "&#8250;", "rsquo" => "&#8217;",
      "rx" => "&#8478;", "sbquo" => "&#8218;", "scaron" => "&#353;", "scruple" => "&#8456;", "sect" => "&#167;",
      "shlig" => "&#383;h", "shy" => "&#173;", "sigma" => "&#963;", "sigmaf" => "&#962;", "spades" => "&#9824;",
      "stigma" => "&#x03DB;", "stlig" => "&#64261;", "sup1" => "&#185;", "sup2" => "&#178;", "sup3" => "&#179;",
      "szlig" => "&#223;", "tau" => "&#964;", "theta" => "&#952;", "thetasym" => "&#977;", "thinsp" => "&#8201;",
      "thorn" => "&#254;", "tilde" => "&#732;", "times" => "&#215;", "trade" => "&#8482;", "uacute" => "&#250;",
      "uarr" => "&#8593;", "ubreve" => "&#365;", "ucirc" => "&#251;", "ugrave" => "&#249;", "umacron" => "&#363;",
      "uml" => "&#168;", "upsih" => "&#978;", "upsilon" => "&#965;", "uuml" => "&#252;", "vacute" => "v&#769;",
      "wyn" => "&#447;", "xi" => "&#958;", "yacute" => "&#253;", "ycirc" => "&#375;", "yen" => "&#165;",
      "ygrave" => "&#7923;", "ymacron" => "&#563;", "yogh" => "&#658;", "yuml" => "&#255;", "zeta" => "&#950;",
      "zwj" => "&#8205;", "zwnj" => "&#8204;"
    }.freeze
    # rubocop:enable Metrics/CollectionLiteralLength
  end
end
