-- phpMyAdmin SQL Dump
-- version 4.0.10.20
-- https://www.phpmyadmin.net
--
-- Host: 172.16.5.222
-- Generation Time: Jun 25, 2019 at 06:30 PM
-- Server version: 5.5.62
-- PHP Version: 5.3.3

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;

--
-- Database: `db1161464_priscian_v2`
--

-- --------------------------------------------------------

--
-- Table structure for table `glosses`
--

CREATE TABLE IF NOT EXISTS `glosses` (
  `recordID` int(11) NOT NULL AUTO_INCREMENT,
  `book` int(11) DEFAULT NULL,
  `subsection` int(11) DEFAULT NULL,
  `code` varchar(2) COLLATE utf8_unicode_ci DEFAULT NULL,
  `ms_ref` varchar(16) COLLATE utf8_unicode_ci DEFAULT NULL,
  `ms_num` int(11) NOT NULL,
  `keil_vol` int(11) DEFAULT NULL,
  `keil_page` int(11) DEFAULT NULL,
  `keil_line` int(11) DEFAULT NULL,
  `types` varchar(50) COLLATE utf8_unicode_ci DEFAULT NULL,
  `text` text COLLATE utf8_unicode_ci NOT NULL,
  `thesaurus_ref` varchar(12) COLLATE utf8_unicode_ci DEFAULT NULL,
  `irish` tinyint(1) NOT NULL,
  `keil_ref` varchar(16) COLLATE utf8_unicode_ci DEFAULT NULL,
  `thesaurus_page` int(11) DEFAULT NULL,
  `translation` varchar(450) CHARACTER SET utf8 DEFAULT NULL,
  `has_analysis` varchar(45) CHARACTER SET utf8 DEFAULT NULL,
  PRIMARY KEY (`recordID`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci AUTO_INCREMENT=13396 ;

--
-- Dumping data for table `glosses`
--

INSERT INTO `glosses` (`recordID`, `book`, `subsection`, `code`, `ms_ref`, `ms_num`, `keil_vol`, `keil_page`, `keil_line`, `types`, `text`, `thesaurus_ref`, `irish`, `keil_ref`, `thesaurus_page`, `translation`, `has_analysis`) VALUES
(1, 0, NULL, 'a', '1a2', 1, 2, 1, 1, '+424+', '<term>omnis</term><gloss>.i. adit <ex>con</ex>atus su<ex>m</ex> usq<ex>ue</ex> gra<ex>m</ex>maticoru<ex>m</ex></gloss> ', NULL, 0, '1,1', NULL, NULL, NULL),
(2, 0, NULL, NULL, '1a2', 1, 2, 1, 1, '+4111+', '<term>omnis</term><gloss><g>.</g> &gt; (ibid.) </gloss><term>eloquentiae</term><gloss><g>.</g></gloss> ', NULL, 0, '1,1', NULL, NULL, NULL),
(8, 0, NULL, NULL, '1a8', 1, 2, 1, 3, '+4143+', '<term>*inve[nio]</term><gloss><g>.-</g> &gt; (1a9=1,3) </gloss><term>et</term><gloss><g>.-</g></gloss> {<i>= K 2r3-5</i> <term>omnis</term> <g>..,</g> &gt; <term>invenio</term> <g>..,</g> &gt; <term>et</term> <g>..,</g> }', NULL, 0, '1,3', NULL, NULL, NULL),
(9, 0, NULL, 'e', '1a10', 1, 2, 1, 3, '+211+', '<term>*libralibus</term><gloss>.i. libardaib</gloss> ', '001a01', 0, '1,3', 49, 'i.e. bookish (arts)', '1'),
(13, 0, NULL, 'f', '1a14', 1, 2, 1, 5, '+543+', '<term>imitari</term><gloss>(m.l.): .i. attá di ṡe<add>i</add>rc la lait<ex>nori</ex> i<ex>n</ex>na g<ex>re</ex>c co·seich<ex>etar</ex> cid a comroicniu</gloss> ', '001a02', 1, '1,5', 49, 'i.e. the Latin grammarians have such love for the Greeks that they follow even their errors', '1'),
(18, 0, NULL, 'h', '1a17', 1, 2, 1, 7, '+211+34+', '<term>tanto</term><gloss>in méit-so</gloss> ', '001a03', 1, '1,7', 49, 'so much', '1'),
(23, 0, NULL, 'k', '1a20', 1, 2, 1, 8, '+543+', '<term>enim</term><gloss>(m.l.): issí t<ex>ra</ex> in dias-sa ro·<supplied>s</supplied>eches<ex>tar</ex>-so<ex>m</ex></gloss> ', '001a04', 1, '1,8', 49, 'it is this couple, then, that he has followed', '1'),
(31, 0, NULL, 'n', '1a29', 1, 2, 1, 13, '+211+36+', '<term>(post) illos</term><gloss>.i. i ndead innaní-sin</gloss> ', '001a05', 1, '1,13', 49, 'i.e. after them', '1'),
(68, 0, NULL, 'a', '2a1', 2, 2, 2, 25, '+51+', '<term>[dignita]tis</term><gloss>in<ex>n</ex>a flaithemnachtae</gloss> ', '002a01', 1, '2,25', 49, 'of the rule', '1'),
(71, 0, NULL, 'c', '2a2', 2, 2, 2, 26, '+211+', '<term>claritudo</term><gloss>.i. in<del>d</del>t airdircus</gloss> ', '002a03', 0, '2,26', 49, 'i.e. the conspicuousness', '1'),
(72, 0, NULL, 'd', '2a4', 2, 2, 2, 27, '+212+', '<term>decoris</term><gloss>ornamen<ex>ti</ex></gloss> ', NULL, 0, '2,27', NULL, NULL, NULL),
(73, 0, NULL, 'e', '2a6', 2, 2, 2, 28, '+3223+', '<term>quorum</term><gloss>.i. animor<ex>um</ex></gloss> ', NULL, 0, '2,28', NULL, NULL, NULL),
(75, 0, NULL, 'g', '2a6', 2, 2, 2, 29, '+51+', '<term>arcem</term><gloss>p<ex>ri</ex>ncipatum</gloss> ', NULL, 0, '2,29', NULL, NULL, NULL),
(84, 0, NULL, 'p', '2a17', 2, 2, 3, 4, '+212+', '<term>discretis</term><gloss>certis</gloss> {<i>= E 3v21</i>}', NULL, 0, '3,4', NULL, NULL, NULL),
(89, 0, NULL, 's', '2a21', 2, 2, 3, 6, '+541+', '<term>generibus</term><gloss>.i. án vocalis án conso<ex>nans</ex></gloss> ', '50', 1, '3,6', 50, NULL, NULL),
(92, 0, NULL, 'u', '2a23', 2, 2, 3, 7, '+541+', '<term>compositiones</term><gloss>.i. ut accentus. d hí c</gloss> ', '002a09', 0, '3,7', NULL, 'i.e. as [=ad-cantus] d into c', '1'),
(120, 0, NULL, 't', '2b26', 2, 2, 4, 5, '+52+', '<term>tertius decimus</term><gloss><g>XIII</g></gloss> ', NULL, 0, '4,5', NULL, NULL, NULL),
(4188, 4, NULL, 'b', '51a8''''', 51, 2, 119, 16, '+211+', '<term>+violentia</term><gloss>écen</gloss> ', '051a01', 1, '119,16', 105, 'violence', '1'),
(4192, 4, NULL, 'f', '51a11"', 51, 2, 119, 21, '+211+572+', '<term>teucria</term><gloss>trói</gloss> {<i>cf. E 34v7</i> .i. troia.}', '051a03', 1, '119,21', 105, 'Troy', '1'),
(4200, 4, NULL, NULL, '51a40', 51, 2, 120, 7, '+11+', '<term>cautéla</term> ', NULL, 0, '120,7', NULL, NULL, NULL),
(4206, 4, NULL, NULL, '51b6', 51, 2, 120, 15, '+4141+', '<term>vero</term><gloss><g>"</g> &gt; (51b9=120,17) </gloss><term>habent</term><gloss><g>"</g></gloss> ', NULL, 0, '120,15', NULL, NULL, NULL),
(4207, 4, NULL, 'b', '51b9', 51, 2, 120, 17, '+34+', '<term>omnimodo</term><gloss>et<ex>ir</ex> aicned 7 suidig<ex>ud</ex></gloss> ', '051b02', 0, '120,17', 105, 'both by nature and position', '1'),
(4209, 4, NULL, 'd', '51b22''''', 51, 2, 120, 19, '+211+', '<term>cocina</term><gloss>cucann</gloss> {<i>cf. E 34v24</i> .i. cochin}', '051b04', 1, '120,19', 105, 'kitchen', '1'),
(4224, 4, NULL, 's', '51b33"', 51, 2, 121, 9, '+3232+', '<term>(cum) illis</term><gloss>lasna anm<ex>m</ex>ann. in .is</gloss> ', '051b10', 0, '121,9', 105, 'with the nouns <ending> in ‘-is’', '1'),
(4227, 4, NULL, 'w', '51b39"', 51, 2, 121, 11, '+211+', '<term>+frugi</term><gloss>parcus</gloss> ', '105', 1, '121,11', 105, NULL, NULL),
(4229, 4, NULL, 'y', '51b42"', 51, 2, 121, 13, '+541+', '<term>mancipi</term><gloss>.i. Ad·co<ex>m</ex>latar-sidi fri cach tuisel 7 ní·dentar cach tuisel díib .,</gloss> {<i>cf. E 35r4</i> om<ex>n</ex>ib<ex>us</ex> cas<ex>ibus</ex> serviunt quando s<ex>un</ex>t monobtota &amp;generibus}', '051b13', 1, '121,13', 105, 'i.e. these are joined to every case, and every case is not made of them', '1');

-- --------------------------------------------------------

--
-- Table structure for table `priscian_lines`
--

CREATE TABLE IF NOT EXISTS `priscian_lines` (
  `recordID` int(11) NOT NULL AUTO_INCREMENT,
  `book` int(11) DEFAULT NULL,
  `subsection` int(11) DEFAULT NULL,
  `keil_vol` int(11) DEFAULT NULL,
  `keil_page` int(11) DEFAULT NULL,
  `keil_line` int(11) DEFAULT NULL,
  `text` text COLLATE utf8_unicode_ci,
  PRIMARY KEY (`recordID`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci AUTO_INCREMENT=66982 ;

--
-- Dumping data for table `priscian_lines`
--

INSERT INTO `priscian_lines` (`recordID`, `book`, `subsection`, `keil_vol`, `keil_page`, `keil_line`, `text`) VALUES
(43738, 0, NULL, 2, 1, 1, 'cum omnis eloquentiae doctrinam et omne studiorum genus '),
(43740, 0, NULL, 2, 1, 3, 'sermone inuenio celebrasse et in omnibus illorum uestigia liberalibus '),
(43742, 0, NULL, 2, 1, 5, 'etiam quosdam errores eorum amore doctorum deceptos imitari, in quibus '),
(43744, 0, NULL, 2, 1, 7, 'quanto sunt iuniores, tanto perspicaciores, et ingeniis floruisse et '),
(43745, 0, NULL, 2, 1, 8, 'diligentia ualuisse omnium iudicio confirmantur eruditissimorum (quid enim '),
(43750, 0, NULL, 2, 1, 13, 'neminem post illos imitatorem eorum extitisse, quippe in neglegentiam '),
(43775, 0, NULL, 2, 2, 25, 'Iuliane consul ac patricie, cui summos dignitatis gradus summa '),
(43776, 0, NULL, 2, 2, 26, 'adquisiuit in omni studio ingenii claritudo, non tantum accipiens ab excelsis '),
(43777, 0, NULL, 2, 2, 27, 'gradibus honorum pretii, quantum illis decoris addens tui, cuius mentem '),
(43778, 0, NULL, 2, 2, 28, 'tam Homeri credo quam Virgilii anima constare, quorum uterque '),
(43779, 0, NULL, 2, 2, 29, 'arcem possederat musicae, te tertium ex utroque compositum esse '),
(43785, 0, NULL, 2, 3, 4, 'facilius, quicquid ex his quaeratur, discretis possit locis inueniri. '),
(43787, 0, NULL, 2, 3, 6, 'litera, de eius generibus et speciebus, de singularum potestate, quae in '),
(43788, 0, NULL, 2, 3, 7, 'quas transeunt per declinationes uel compositiones partium orationis. '),
(43812, 0, NULL, 2, 4, 5, 'duodecimus et tertiusdecimus de pronomine. '),
(46432, 4, NULL, 2, 119, 16, 'uiolenti uiolentĭa, superbus superbi superbĭa, modestus modesti '),
(46437, 4, NULL, 2, 119, 21, 'Tuscia, Graecus Graeci Graecia, Teucrus uel Teucer Teucri Teucria. '),
(46450, 4, NULL, 2, 120, 7, 'la e longa antecedente: cautus cauti cautēla, tutus tuti tutēla, '),
(46458, 4, NULL, 2, 120, 15, 'na uero desinentia denominatiua siue uerbalia, de quibus iam '),
(46460, 4, NULL, 2, 120, 17, 'omnimodo longam habent paenultimam uel natura uel positione: officium '),
(46462, 4, NULL, 2, 120, 19, 'doctrīna, tonstrix tonstrīna, cocus cocīna et culīna, cantus '),
(46476, 4, NULL, 2, 121, 9, 'melius cum illis tractabuntur. '),
(46478, 4, NULL, 2, 121, 11, 'a fruge, nihili a nihilo. quidam enim figurate frugi datiuum et nihili '),
(46480, 4, NULL, 2, 121, 13, 'irrationabiliter dicunt, sicut mancipi et nec mancipi et cordi et ');

-- --------------------------------------------------------

--
-- Table structure for table `types`
--

CREATE TABLE IF NOT EXISTS `types` (
  `recordID` int(11) NOT NULL AUTO_INCREMENT,
  `code` varchar(4) COLLATE utf8_unicode_ci NOT NULL,
  `description` varchar(100) COLLATE utf8_unicode_ci NOT NULL,
  PRIMARY KEY (`recordID`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci AUTO_INCREMENT=87 ;

--
-- Dumping data for table `types`
--

INSERT INTO `types` (`recordID`, `code`, `description`) VALUES
(1, '11', 'length mark indicating syllable length in poetic quotations'),
(2, '12', 'glosses on the length of syllables'),
(3, '13', 'elaborate comment on metre'),
(4, '211', 'trans. into Old Irish'),
(5, '212', 'synonyms'),
(6, '213', 'negated antonyms'),
(7, '214', 'hyponym defined by a hypernym with differentia specifica'),
(8, '215', 'definition given by an entire sentence'),
(9, '221', 'Greek glosses and glosses over Greek words'),
(10, '222', 'use of different prefixes'),
(11, '223', 'adjectives glossed with a noun in the genitive (or another case)'),
(12, '23', 'differentiae'),
(13, '24', 'further derivations in a gloss'),
(14, '24', 'glosses showing the original form of the word'),
(15, '31', 'grammatical glosses on the noun'),
(16, '311', 'glosses on case forms'),
(17, '3111', 'glosses on case: nominative'),
(18, '3112', 'glosses on case: vocative'),
(19, '3113', 'glosses on case: genitive'),
(20, '3114', 'glosses on case: dative'),
(21, '3115', 'glosses on case: accusative'),
(22, '3116', 'glosses on case: ablative'),
(23, '312', 'glosses on number'),
(24, '313', 'glosses on gender and various other morphological points'),
(25, '32', 'grammatical glosses on the pronoun'),
(26, '321', 'glosses on pronouns in general'),
(27, '322', 'glosses on relative pronouns'),
(28, '3221', 'rel. pronoun glossed by its antecedent'),
(29, '3222', 'rel. pronoun glossed by the gloss above the antecedent'),
(30, '3223', 'rel. pronoun glossed by an interpretation or lexical equivalent of the antecedent'),
(31, '3223', 'rel. pronoun without identifiable antecedent'),
(32, '323', 'other pronouns'),
(33, '3231', 'interchangeability of demonstrative pronouns or Old Irish glosses solving ambiguity'),
(34, '3232', 'glosses over pronouns referring to a concept in the preceding/following line/paragraph'),
(35, '3233', 'glosses which differ in case from the pronoun and can substitute it'),
(36, '33', 'grammatical glosses on the verb and the participle'),
(37, '331', 'general glosses on morphology'),
(38, '332', 'morphological glosses on tense'),
(39, '333', 'morphological glosses on mood'),
(40, '334', 'morphological glosses on the participle and the gerund'),
(41, '34', 'grammatical glosses on the adverb'),
(42, '35', 'grammatical glosses on the conjunction'),
(43, '36', 'grammatical glosses on the preposition'),
(44, '37', 'grammatical glosses on the interjection'),
(45, '41', 'syntactical glosses using symbols'),
(46, '4111', 'symbols correlating adjectives/prepositions with substantives'),
(47, '4112', 'symbols correlating a genitive in apposition with a substantive'),
(48, '4121', 'symbols correlating a rel. pronoun with its antecedent'),
(49, '4122', 'symbols correlating other pronouns with nouns'),
(50, '4123', 'symbols correlating verbal forms, verbs—subjects, etc.'),
(51, '413', 'glosses establishing word order with the help of different symbols'),
(52, '4141', 'symbols clarifying the skeletal structure of a sentence'),
(53, '4142', 'symbols correlating two sentences'),
(54, '4143', 'symbols supplying word(s) ommited by the author'),
(55, '4144', 'symbols correlating theoretical explanation with examples'),
(56, '4145', 'various other uses'),
(57, '42', 'syntactical glosses using words'),
(58, '421', 'glosses identifying a speaker or an example'),
(59, '422', 'suppletive glosses'),
(60, '4221', 'suppletive nouns/pronouns in the nominative'),
(61, '4222', 'suppletive nouns/pronouns in the genitive'),
(62, '4223', 'suppletive nouns/pronouns in the dative'),
(63, '4224', 'suppletive nouns/pronouns in the accusative'),
(64, '4225', 'suppletive nouns/pronouns in the vocative'),
(65, '4226', 'suppletive adverbial adjuncts'),
(66, '4227', 'suppletive adjectives and adjectival clauses'),
(67, '4228', 'suppletive verbs and short clauses'),
(68, '4229', 'suppletive conjunctions or prepositions'),
(69, '423', 'glosses modifying adjectives'),
(70, '424', '<i>adit</i> glosses'),
(71, '51', 'glosses decoding figures of speech'),
(72, '52', 'glosses summarizing content'),
(73, '53', 'cross-references'),
(74, '541', '(elaborate) comment on the main text'),
(75, '542', '<i>quia</i> glosses'),
(76, '543', 'glosses elucidating the main text'),
(77, '55', 'etymological glosses'),
(78, '56', 'encyclopedic glosses'),
(79, '561', 'geographical names'),
(80, '562', 'unusual objects'),
(81, '563', 'proper names'),
(82, '57', 'source glosses'),
(83, '571', 'grammatical sources identified/Priscian confronted with other sources'),
(84, '572', 'glosses revealing an acquaintance with Latin authors or Roman mythology'),
(85, '58', 'glosses giving variant readings'),
(86, '59', 'glosses giving information about the socio-historical context');

-- --------------------------------------------------------

--
-- Table structure for table `word_instances`
--

CREATE TABLE IF NOT EXISTS `word_instances` (
  `recordID` int(11) NOT NULL AUTO_INCREMENT,
  `glossID` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `word_instance` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `headword` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `DIL_headword` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `wordclass` varchar(75) COLLATE utf8_unicode_ci DEFAULT NULL,
  `subclass` varchar(75) COLLATE utf8_unicode_ci DEFAULT NULL,
  `breakdown` varchar(150) COLLATE utf8_unicode_ci DEFAULT NULL,
  `meaning` varchar(200) COLLATE utf8_unicode_ci DEFAULT NULL,
  `submeaning` varchar(150) COLLATE utf8_unicode_ci DEFAULT NULL,
  `analysis` varchar(75) COLLATE utf8_unicode_ci DEFAULT NULL,
  `mutation` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `voice` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `rel` varchar(5) COLLATE utf8_unicode_ci DEFAULT NULL,
  `dep` varchar(1) COLLATE utf8_unicode_ci DEFAULT NULL,
  `old_recordID` int(11) DEFAULT NULL,
  `word_instance_index` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `headword_index` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  PRIMARY KEY (`recordID`)
) ENGINE=InnoDB  DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci AUTO_INCREMENT=52708 ;

--
-- Dumping data for table `word_instances`
--

INSERT INTO `word_instances` (`recordID`, `glossID`, `word_instance`, `headword`, `DIL_headword`, `wordclass`, `subclass`, `breakdown`, `meaning`, `submeaning`, `analysis`, `mutation`, `voice`, `rel`, `dep`, `old_recordID`, `word_instance_index`, `headword_index`) VALUES
(35182, '9', 'libardaib', 'lebarda', 'lebarda', 'adjective', 'i̯o, i̯ā', NULL, 'bookish', NULL, 'dat.pl.', NULL, '', '', NULL, 1, 'libardaib', 'lebarda'),
(35183, '13', 'at', 'ad 1', 'ad-', 'particle', 'preverb', NULL, '', NULL, '*ad-tā- (*bw-)', NULL, '', '', NULL, 2, 'at', 'ad '),
(35184, '13', 'at·tá', 'at·tá', 'attá', 'verb', 'substantive verb', NULL, '', NULL, '3sg.pres.ind.', NULL, 'Active', '', NULL, 3, 'attá', 'attá'),
(35185, '13', 'di', 'de 1', '1 de', 'preposition, with dat; leniting', '', NULL, 'origin, source, authority', NULL, 'dat.', NULL, '', '', NULL, 4, 'di', 'de '),
(35186, '13', 'ṡe(i)rc', 'serc', 'serc', 'noun', 'f, ā', NULL, 'love', NULL, 'dat.sg.', NULL, '', '', NULL, 5, 'ṡeirc', 'serc'),
(35187, '13', 'la', 'la', 'la', 'preposition, with acc; geminating', '', NULL, 'possession, ownership, association', NULL, 'acc.', NULL, '', '', NULL, 6, 'la', 'la'),
(35188, '13', 'laitnori', 'Laitneóir', 'Laitneóir', 'noun', 'm, i', NULL, 'Latin grammarian, Latin writer', NULL, 'acc.pl.', NULL, '', '', NULL, 7, 'laitnori', 'Laitneóir'),
(35189, '13', 'inna', 'in 1', '1 in', 'article', 'm', NULL, 'with subst or pronom followed by rel clause', NULL, 'gen.pl.', NULL, '', '', NULL, 8, 'inna', 'in '),
(35190, '13', 'grec', 'gréc', 'gréc', 'noun', 'm, o', NULL, 'Greek', NULL, 'gen.pl.', NULL, '', '', NULL, 9, 'grec', 'gréc'),
(35191, '13', 'co', 'co 4', '3 co', 'conjunction (nasalizing, conjunct)', '', NULL, 'consecutive: so that, that', NULL, '', NULL, '', '', NULL, 10, 'co', 'co '),
(35192, '13', 'seichetar', 'sechithir', 'seichithir', 'verb', 'BII', NULL, 'follows, pursues', NULL, '3pl.pres.ind.', NULL, 'Active', '', NULL, 11, 'seichetar', 'sechithir'),
(35193, '13', 'ci', 'cía 2', '2 cía', 'conjunction', 'concessive and explicative (leniting)', NULL, 'adverbial: even, too', NULL, '', NULL, '', '', NULL, 12, 'ci', 'cía '),
(35194, '13', 'd', 'is', '1 is', 'verb', 'copula', NULL, '', NULL, '3sg.pres.subj.', NULL, 'Active', '', NULL, 13, 'd', 'is'),
(35195, '13', 'a', 'a 4', '2 a', 'pronoun, possessive, unstressed', '3pl (nasalizing)', NULL, 'possession, ownership, association', NULL, '', NULL, '', '', NULL, 14, 'a', 'a '),
(35196, '13', 'comroicniu [leg. comroircniu]', 'comrorcun', 'comrorcun', 'noun', 'f, ā', NULL, 'error, mistake, delusion', NULL, 'acc.pl.masc.', NULL, '', '', NULL, 15, 'comroicniu [leg. comroircniu]', 'comrorcun'),
(35197, '18', 'in', 'in 2', '1 in', 'article', 'fem', NULL, 'with subst and adj, dem pron, adv ', NULL, 'dat.sg.', NULL, '', '', NULL, 16, 'in', 'in '),
(35198, '18', 'méit', 'méit', 'méit', 'noun', 'f, mixed ā-, ī-, i-', NULL, 'size, quantity', NULL, 'dat.sg.', NULL, '', '', NULL, 17, 'méit', 'méit'),
(35199, '18', 'so', 'so 1', '1 so', 'adjective, demonstrative pronominal', 'this, these', NULL, 'adjectival (enclitic): this, these', NULL, '', NULL, '', '', NULL, 18, 'so', 'so '),
(35200, '23', 'is', 'is', '1 is', 'verb', 'copula', NULL, '', NULL, '3sg.pres.ind.', NULL, 'Active', '', NULL, 19, 'is', 'is'),
(35201, '23', 'sí', 'sí 1', '1 si', 'pronoun, personal', '3sg f', NULL, 'proleptic', NULL, '', NULL, '', '', NULL, 20, 'sí', 'sí '),
(35202, '23', 'tra', 'trá', 'trá', 'adverb', 'conjunctive', NULL, 'followed by a clause: then, therefore, now', NULL, '', NULL, '', '', NULL, 21, 'tra', 'trá'),
(35203, '23', 'in', 'in 2', '1 in', 'article', 'fem', NULL, 'with subst and adj, dem pron, adv', NULL, 'nom.sg.', NULL, '', '', NULL, 22, 'in', 'in '),
(35204, '23', 'dias', 'días', '2 días', 'noun', 'f, ā', NULL, 'pair, couple (used of persons only, whereas dede is used of things)', NULL, 'nom.sg.', NULL, '', '', NULL, 23, 'dias', 'días'),
(35205, '23', 'sa', 'so 1', '1 so', 'adjective, demonstrative pronominal', 'this, these', NULL, 'adjectival (enclitic): that, those', NULL, '', NULL, '', '', NULL, 24, 'sa', 'so '),
(35206, '23', 'ro', 'ro 1', '1 ro', 'particle', 'preverb', NULL, 'perfective particle', NULL, '', NULL, '', '', NULL, 25, 'ro', 'ro '),
(35207, '23', 'ro·<s>echestarsom', 'sechithir', 'seichithir', 'verb', 'BII', NULL, 'follows, pursues', NULL, '3sg.perf.', NULL, 'Active', 'Y', NULL, 26, 'ro<s>echestarsom', 'sechithir'),
(35208, '23', 'som', '-som 1', 'som', 'particle, emphatic pronominal', '3sg m, n', NULL, 'as subject of verb', NULL, '3sg.masc.', NULL, '', '', NULL, 27, 'som', 'som '),
(35209, '31', 'i', 'i 2', 'i', 'preposition, with dat and acc; nasalizing', '', NULL, 'forming preposition and adverbial phrases: i n-dead “after”', NULL, 'acc.', NULL, '', '', NULL, 28, 'i', 'i '),
(35210, '31', 'n-dead', 'dead 1', 'dead', 'noun', 'n, o', NULL, 'end, conclusion', NULL, 'acc.sg.', NULL, '', '', NULL, 29, 'ndead', 'dead '),
(35211, '31', 'inna', 'in 1', '1 in', 'article', 'm', NULL, 'followed by indecl accented deictic pron (h)í and sin', NULL, 'gen.pl.', NULL, '', '', NULL, 30, 'inna', 'in '),
(35212, '31', 'n-í', 'í 1', '4 í', 'pronoun, indeclinable, accented, deictic', '', NULL, 'with article and followed by siu, sin, thall', NULL, 'gen.pl.masc.', NULL, '', '', NULL, 31, 'ní', 'í '),
(35213, '31', 'sin', 'sin', '1 sin', 'pronoun, demonstrative', 'that, those', NULL, 'adjectival (enclitic): that, those', NULL, '', NULL, '', '', NULL, 32, 'sin', 'sin'),
(35225, '68', 'inna', 'in 2', '1 in', 'article', 'fem', NULL, 'with subst in genitive', NULL, 'gen.sg.', NULL, '', '', NULL, 44, 'inna', 'in '),
(35226, '68', 'flaithemnachtæ', 'flaithemnacht', 'flaithemnacht', 'noun', 'f, ā', NULL, 'princedom', NULL, 'gen.sg.', NULL, '', '', NULL, 45, 'flaithemnachtæ', 'flaithemnacht'),
(35233, '71', 'inḍt', 'in 1', '1 in', 'article', 'm', NULL, 'with subst alone', NULL, 'nom.sg.', NULL, '', '', NULL, 52, 'inḍt', 'in '),
(35234, '71', 'airdircus', 'airdircus', 'airdircus', 'noun', 'm, u', NULL, 'conspicuousness', NULL, 'nom.sg.', NULL, '', '', NULL, 53, 'airdircus', 'airdircus'),
(35281, '92', 'hí', 'i 2', 'i', 'preposition, with dat and acc; nasalizing', '', NULL, 'Location: state or condition in which or into which: in, at, into, to', NULL, 'acc./dat.', NULL, '', '', NULL, 100, 'hí', 'i '),
(41078, '4188', 'écen', 'éicen', 'éicen', 'noun', 'f, ā', NULL, 'violence', NULL, 'nom.sg.', NULL, '', '', NULL, 5947, 'écen', 'éicen'),
(41080, '4192', 'trói', 'troí', 'Troí', 'noun, proper', '', NULL, 'Troy', NULL, 'nom.sg.', NULL, '', '', NULL, 5949, 'trói', 'troí'),
(41100, '4207', 'etir', 'eter 1', 'eter', 'preposition, with acc', '', NULL, 'both', NULL, 'acc.', NULL, '', '', NULL, 5969, 'etir', 'eter '),
(41101, '4207', 'aicned', 'aicned', '1 aicned', 'noun', 'n, o', NULL, 'nature, inherent quality, essence', NULL, 'acc.sg.', NULL, '', '', NULL, 5970, 'aicned', 'aicned'),
(41102, '4207', '7', 'ocus', '2 ocus', 'conjunction (leniting)', 'coordinating', NULL, 'and', NULL, 'joining two nouns', NULL, '', '', NULL, 5971, '', 'ocus'),
(41103, '4207', 'suidigud', 'suidiugud', 'suidiugad', 'noun', 'm, o', NULL, 'position', NULL, 'acc.sg.', NULL, '', '', NULL, 5972, 'suidigud', 'suidiugud'),
(41105, '4209', 'cucann', 'cucann', 'cucann', 'noun', 'f, ā', NULL, 'kitchen', NULL, 'nom.sg.', NULL, '', '', NULL, 5974, 'cucann', 'cucann'),
(41117, '4224', 'la', 'la', 'la', 'preposition, with acc; geminating', '', NULL, 'associative sense', NULL, 'acc. + def.art.pl.', NULL, '', '', NULL, 5986, 'la', 'la'),
(41118, '4224', 'sna', 'a 8', '1 in', 'article', 'n', NULL, 'with prep and substantive', NULL, 'acc.pl. + la', NULL, '', '', NULL, 5987, 'sna', 'a '),
(41119, '4224', 'anmmann', 'ainm', 'ainm', 'noun', 'n, n', NULL, 'noun', NULL, 'acc.pl.', NULL, '', '', NULL, 5988, 'anmmann', 'ainm'),
(41120, '4224', 'in', 'i 2', 'i', 'preposition, with dat and acc; nasalizing', '', NULL, 'Location: after verbs of changing, putting dividing, ending, etc.', NULL, 'dat.', NULL, '', '', NULL, 5989, 'in', 'i '),
(41132, '4229', 'Ad', 'ad 1', 'ad-', 'particle', 'preverb', NULL, '', NULL, '*ad-com-lā', NULL, '', '', NULL, 6001, 'Ad', 'ad '),
(41133, '4229', 'com', 'con', '1 com-', 'particle', 'preverb', NULL, '', NULL, '*ad-com-lā', NULL, '', '', NULL, 6002, 'com', 'con'),
(41134, '4229', 'Ad·comlatarsidi', 'ad·comla', 'ad-comla', 'verb', 'AI', NULL, 'joins, unites', NULL, '3pl.pres.ind.pass.', NULL, 'Passive', '', NULL, 6003, 'Adcomlatarsidi', 'adcomla'),
(41135, '4229', 'sidi', 'side', '2 side', 'pronoun, anaphoric', 'enclitic', NULL, 'as subject of verb', NULL, 'nom.pl.', NULL, '', '', NULL, 6004, 'sidi', 'side'),
(41136, '4229', 'fri', 'fri', 'fri', 'preposition, with acc; geminating', '', NULL, 'figurative direction: purpose, aim', NULL, 'acc.', NULL, '', '', NULL, 6005, 'fri', 'fri'),
(41137, '4229', 'cach', 'cach 2', 'cach ', 'adjective, pronominal (preceding noun)', '', NULL, 'every', NULL, 'acc.sg.masc.', NULL, '', '', NULL, 6006, 'cach', 'cach '),
(41138, '4229', 'tuisel', 'tuisel', 'tuisel', 'noun', 'm, o', NULL, 'gramm. case', NULL, 'acc.sg.', NULL, '', '', NULL, 6007, 'tuisel', 'tuisel'),
(41139, '4229', '7', 'ocus', '2 ocus', 'conjunction (leniting)', 'coordinating', NULL, 'and', NULL, 'joining two sentences or clauses', NULL, '', '', NULL, 6008, '', 'ocus'),
(41140, '4229', 'ní', 'ní 5', '3 ní', 'particle', 'negative', NULL, 'with other verbs', NULL, '', NULL, '', '', NULL, 6009, 'ní', 'ní '),
(41141, '4229', 'de', 'de 5', 'n/a', 'particle', 'preverb', NULL, '', NULL, '*de-gnī-', NULL, '', '', NULL, 6010, 'de', 'de '),
(41142, '4229', 'ní·dentar', 'do·gní', 'do-gní', 'verb', 'AIII', NULL, 'does, makes', NULL, '3sg.pres.ind.pass.', NULL, 'Passive', '', NULL, 6011, 'nídentar', 'dogní'),
(41143, '4229', 'cach', 'cach 2', 'cach ', 'adjective, pronominal (preceding noun)', '', NULL, 'every', NULL, 'nom.sg.masc.', NULL, '', '', NULL, 6012, 'cach', 'cach '),
(41144, '4229', 'tuisel', 'tuisel', 'tuisel', 'noun', 'm, o', NULL, 'gramm. case', NULL, 'nom.sg.', NULL, '', '', NULL, 6013, 'tuisel', 'tuisel'),
(41145, '4229', 'díib', 'de 1', '1 de', 'preposition, with dat; leniting', '', NULL, 'partitive', NULL, 'dat. + suff.pron.3pl.', NULL, '', '', NULL, 6014, 'díib', 'de ');

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
