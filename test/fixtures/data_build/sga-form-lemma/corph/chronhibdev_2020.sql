-- phpMyAdmin SQL Dump
-- version 4.9.5
-- https://www.phpmyadmin.net/
--
-- Host: localhost:3306
-- Generation Time: Apr 23, 2021 at 03:58 AM
-- Server version: 10.3.28-MariaDB
-- PHP Version: 7.3.27

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET AUTOCOMMIT = 0;
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `chronhibdev_2020`
--

-- --------------------------------------------------------

--
-- Table structure for table `BIBLIOGRAPHY`
--

CREATE TABLE `BIBLIOGRAPHY` (
  `ID` int(11) NOT NULL,
  `Abbreviation` varchar(45) COLLATE utf8_unicode_ci DEFAULT NULL,
  `Reference` varchar(2000) COLLATE utf8_unicode_ci DEFAULT NULL,
  `Pdf_Link` text COLLATE utf8_unicode_ci NOT NULL,
  `Image` text COLLATE utf8_unicode_ci NOT NULL,
  `Sort_ID` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

-- Dumping data for table `BIBLIOGRAPHY` (trimmed for the sga/form-lemma fixture: see README.md)
--

INSERT INTO `BIBLIOGRAPHY` (`ID`, `Abbreviation`, `Reference`, `Pdf_Link`, `Image`, `Sort_ID`) VALUES
(7, 'Bauer 2015a', 'Bauer, Bernhard, The online database of the Old Irish Priscian glosses, Online: Indogermanistik Wien. URL: <http://www.univie.ac.at/indogermanistik/priscian/>', '', '', NULL),
(25, 'Thes.', 'Stokes, Whitley & Strachan, John, Thesaurus Palaeohibernicus (2 vols.), Cambridge: Cambridge University Press, 1901–1903.', '', '', NULL),
(259, 'Bauer 2015b', 'Bauer, Bernhard, The online database of the Old Irish Priscian glosses (v 2.0), in: Stifter et al. 2021, online at: https://chronhib.maynoothuniversity.ie. ', '', '', NULL);

CREATE TABLE `LEMMATA` (
  `ID` int(11) NOT NULL,
  `Lemma` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Meaning` text COLLATE utf8mb4_bin NOT NULL,
  `DIL_Headword` text COLLATE utf8mb4_bin NOT NULL,
  `Part_Of_Speech` text COLLATE utf8mb4_bin NOT NULL,
  `Class` text COLLATE utf8mb4_bin NOT NULL,
  `Gender` varchar(45) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Etymology` text COLLATE utf8mb4_bin NOT NULL,
  `Comments` text COLLATE utf8mb4_bin NOT NULL,
  `Lang` varchar(45) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Sort_ID` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Dumping data for table `LEMMATA` (trimmed for the sga/form-lemma fixture: see README.md)
--

INSERT INTO `LEMMATA` (`ID`, `Lemma`, `Meaning`, `DIL_Headword`, `Part_Of_Speech`, `Class`, `Gender`, `Etymology`, `Comments`, `Lang`, `Sort_ID`) VALUES
(3, '.i.', 'id est, it is', '', '', '', '', '', '', '', 3),
(5, 'len.rel.particle', 'leniting relative particle', '', 'particle_relative', '', '', '*i̯o', '', 'Early Irish', 5),
(10, '3pl.poss.pron.', 'their', 'www.dil.ie/3  ', 'pronoun_possessive', '', '', '*ei̯sōm', '', 'Early Irish', 10),
(14, '3sg.masc./neut.poss.pron.', 'his, its', 'www.dil.ie/3  ', 'pronoun_possessive', '', '', '*esi̯o', '', 'Early Irish', 14),
(40, 'ad· 1', 'aspectual and lexicalized meanings', 'www.dil.ie/247 ', 'particle_preverb', '', '', '*ad ; *ati', '', 'Early Irish', 40),
(223, 'ar 1', 'in front of, for the sake of, in return for, on account of, because of; against (as protection); abstract: by virtue of, by means of, through', 'www.dil.ie/3902 ', 'preposition', 'acc./dat.', '', '*φari', '', 'Early Irish', 223),
(281, 'ad·tá', 'to be, to exist, ', 'www.dil.ie/4927 ', 'verb', 'H1', '', '*(ad-)tā- in pres. ind., but *u̯el- (S1), *beu̯- (H2), etc. in other stems', 'The headword shows assimilation of the final <d> of the preverb to the initial <t> of the verbal root. In dependent forms one preverb is dropped (cf. ad·áglathar, do·tuit, fo·fúasna, fo·gaib [fo·fúair vs ní·fúair], imm·imgaib, ro·cluinethar, ro·fitir/ro·finnathar, ro·laimethar). See GOI §543.', 'Early Irish', 281),
(460, 'cach', 'every, each, all, any ', 'www.dil.ie/7528 ', 'adjective_quantifier', 'o/ā', '', '*ku̯āku̯o/ā-, in unstressed position shortened.', '', 'Early Irish', 460),
(731, 'con· 1', 'aspectual and lexicalized meanings', 'www.dil.ie/10554', 'particle_preverb', '', '', '*kom', '', 'Early Irish', 731),
(888, 'cucann', 'kitchen', 'www.dil.ie/13411', 'noun', 'ā', 'fem.', '< Lat. cocīna', '', 'Early Irish', 888),
(964, 'di', 'away, from, cause or reason, by', 'www.dil.ie/14787', 'preposition', 'dat.', '', '*de, dī', '', 'Early Irish', 964),
(968, 'de·, dí·', 'aspectual and lexicalized meanings', 'n/a', 'particle_preverb', '', '', '*de, dī', '', 'Early Irish', 968),
(969, 'deäd', 'end, conclusion', 'www.dil.ie/14812 ', 'noun', 'o', 'neut.', '*dīu̯edo-', 'Sometimes inflected as a fem. ā-stem.', 'Early Irish', 969),
(1067, 'do 1', 'to, for, by etc.', 'www.dil.ie/17096 ', 'preposition', 'dat.', '', '*dū, *do', '', 'Early Irish', 1067),
(1076, 'do·gní', 'to do, to make', 'www.dil.ie/17752', 'verb', 'H2', '', '*dī-gnī-', '', 'Early Irish', 1076),
(1218, 'éicen', 'necessity, compulsion, violence, in response to a question, indeed, surely, of truth', 'www.dil.ie/19711', 'noun', 'ā', 'fem.', '', '', 'Early Irish', 1218),
(1294, 'eter', 'between, among; both...and... ', 'www.dil.ie/20789', 'preposition', 'acc.', '', '*enter', '', 'Early Irish', 1294),
(1567, 'fri', 'towards, against, standard of comparison ', 'www.dil.ie/24329', 'preposition', 'acc.', '', '*u̯riti (Schrijver Ériu 45.158) ; fri < *writh ; *u̯rit', 'look at usages of fri', 'Early Irish', 1567),
(1715, 'i', 'in, into', 'www.dil.ie/26891', 'preposition', 'acc./dat.', '', 'before suffixed pron. *ande ; *eni; inflected forms from *and-', '', 'Early Irish', 1715),
(1773, 'in 1', 'the, definite article', 'www.dil.ie/28194 ', 'definite_article', 'o/ā', '', '*sind-o/ā-; neuter is possibly from *som.', '', 'Early Irish', 1773),
(1830, 'is 1', 'to be, the copula', 'www.dil.ie/29104', 'verb', 'copula', '', '*est, etc. other stems based on *beu̯-', '', 'Early Irish', 1830),
(1861, 'la', 'with, by, along with, and, in addition to, as well as, on account of, because of, by reason of', 'www.dil.ie/29233', 'preposition', 'acc.', '', '*φleti (Schrijver Ériu 45.158)', '', 'Early Irish', 1861),
(2081, 'méit', 'size, quantity, as rel. adv. introducing a subord. clause: as much as, as far as, to the extent that amount, so much, Greatness, magnitude (of size, quantity, number, extent, degree)', 'www.dil.ie/31852', 'noun', 'ī', 'fem.', '*mantī-; méit was originally an ī-stem, which at some point became an ā-stem mét, with the (occasional) possiblity to have dative/accusative mét.', '', 'Early Irish', 2081),
(2249, 'nert', 'strength, force', 'www.dil.ie/33116', 'noun', 'o', 'neut.', '*nerto-', '', 'Early Irish', 2249),
(2254, 'ní 3', 'not', 'www.dil.ie/33147 ', 'particle_negative_main', '', '', '*ne, nē ; *ne', '', 'Early Irish', 2254),
(2286, 'nota augens', 'emphasising particle', 'www.dil.ie/37352 : www.dil.ie/38194 : www.dil.ie/37354', 'particle_pronominal', '', '', '', '', 'Early Irish', 2286),
(2324, 'ocus 2', 'coordinating: and, since ', 'www.dil.ie/33483 : www.dil.ie/33484', 'conjunction', '', '', '*onkus + relative copula (Aaron Griffith’s etymology) ', '', 'Early Irish', 2324),
(2388, 'ós 1', 'over, above', 'www.dil.ie/34047 ', 'preposition', 'dat.', '', '*ou̯χs', '', 'Early Irish', 2388),
(2586, 'ro· 2', 'with pres. ind. and subj. with perfective sense; to express potentiality or possibility, with all forms of the verb ; perfective augment', 'www.dil.ie/35364 ', 'particle_augment', '', '', '*φro', '', 'Early Irish', 2586),
(2767, 'sin', 'that one, those ones, the one in there ; that, those', 'www.dil.ie/37567 ', 'pronoun_demonstrative_distal', '', '', '', 'stressed without article analyse pronoun\nunstressed with article and noun no analysis demonstrative particle substantival use', 'Early Irish', 2767),
(3108, 'ut', 'that, so that', '', 'conjunction', '', '', '', '', 'Latin', 3108),
(3143, 'ad·comla', 'to join, to unite, to combine', 'www.dil.ie/400', 'verb', 'W1', '', '*ad-kom-lā-', '', 'Early Irish', 3143),
(3210, 'aicned', 'nature, inherent quality, essence ', 'www.dil.ie/808 ', 'noun', 'o', 'neut.', '*ad-gen-e-to- / ad-gen-i-to- (LEIA A-26)', '', 'Early Irish', 3210),
(3238, 'ainm', 'name, noun (gramm) ', 'www.dil.ie/1436', 'noun', 'n', 'neut.', '*anman', '', 'Early Irish', 3238),
(3690, 'cía 2', 'concessive and explicative: even, although', 'www.dil.ie/8966 ', 'conjunction', '', '', '', '', 'Early Irish', 3690),
(3735, 'co 4', 'so that, until (+independent, leniting)', 'www.dil.ie./9788', 'complementiser', '', '', '*ku̯us', '', 'Early Irish', 3735),
(3825, 'comrorgun', 'the act of erring; error, mistake, delusion', 'www.dil.ie/11688 ', 'verbal_noun', 'ā', 'fem.', 'vn. of *con·erairg', '', 'Early Irish', 3825),
(4321, 'doidnge', 'difficulty, perplexity, trouble', 'www.dil.ie/17805', 'noun', 'i̯ā', 'fem.', 'abstract < *do- + *daing', '', 'Early Irish', 4321),
(4629, 'flaithemnacht', 'rule, sovereignty; princedom', 'www.dil.ie/22287', 'noun', 'ā', 'fem.', '', '', 'Early Irish', 4629),
(4941, 'gréc 1', 'Greek (person)', 'www.dil.ie/26552 ', 'noun', 'o', 'masc.', '', '', 'Early Irish', 4941),
(4958, 'í 1', 'that ; substantivizing particle', '', 'pronoun_propword', '', '', '*ī', '', 'Early Irish', 4958),
(5709, 'seichithir', 'to follow, to pursue', 'www.dil.ie/36883', 'verb', 'S2', '', '', '', 'Early Irish', 5709),
(5732, 'serc', 'the act of loving; love, affection', 'www.dil.ie/37233', 'verbal_noun', 'ā', 'fem.', '*serk-ā-; vn. of caraid', '', 'Early Irish', 5732),
(5739, '3sg.fem.indp.pron.', 'she, her, it', 'www.dil.ie/37352 ', 'pronoun_independent', '', '', '', '', 'Early Irish', 5739),
(5837, 'suidiugud', 'the act of placing, putting; position', 'www.dil.ie/39209 ', 'verbal_noun', 'u', 'masc.', 'vn. of suidigidir', '', 'Early Irish', 5837),
(6031, 'trá', 'then, therefore, so, indeed, however, but', 'www.dil.ie/41529', 'particle_discourse', '', '', 'grammaticalized from tráth ‘period of time, hour’', '', 'Early Irish', 6031),
(7008, 'airdaircus', 'conspicuousness', 'www.dil.ie/1846 ', 'noun', 'u', 'masc.', '', '', 'Early Irish', 7008),
(7138, 'Cai', 'Cai', 'n/a', 'proper_noun', 'indecl.(?)', 'masc.', '', '', 'Early Irish', 7138),
(7580, 'Laitneóir', 'Latin grammarian, Latin writer, Latinist, Latin people', 'www.dil.ie/29505', 'noun', 'i', 'masc.', 'denominative (+ agent suffix -(e)óir): Laiten', '', 'Early Irish', 7580),
(7590, 'lebardae', 'bookish', 'www.dil.ie/29669 ', 'adjective', 'i̯o/i̯ā', '', '', '', 'Early Irish', 7590),
(7908, 'Troí', 'Troy', 'www.dil.ie/42008', 'proper_noun', 'indecl.(?)', '', '', '', 'Early Irish', 7908),
(7919, 'tuisel', 'gramm. case', 'www.dil.ie/42405 ', 'noun', 'o', 'masc.', '', '', 'Early Irish', 7919),
(7964, '-so', 'this, these', '', 'particle_demonstrative_proximate', '', '', '*so, sā, sod, etc. with various suffixes.', '', 'Early Irish', 7964),
(8109, '-side', 'that one, he, she, it, they', 'www.dil.ie/37463', 'particle_anaphoric', 'i̯o/i̯ā', '', '', '', 'Early Irish', 8109),
(8836, 'diäs', 'pair, couple', 'www.dil.ie/15982', 'noun', 'ā', 'fem.', '', '', 'Early Irish', 8836),
(9497, '(Latin letters and suffixes)', '', '', 'noun', '', '', '', '', 'Latin', 9497),
(9959, 'accentus', '', '', 'noun', '', 'masc.', '', '', 'Latin', NULL);

CREATE TABLE `MORPHOLOGY` (
  `ID` int(11) NOT NULL,
  `Text_Unit_ID` varchar(20) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Stressed_Unit` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Morph` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Expected_Morph` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Lemma` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Secondary_Meaning` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Analysis` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Syntactic_Context` varchar(255) COLLATE utf8mb4_bin NOT NULL,
  `Comments` varchar(2000) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Augm` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Rel` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Trans` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Depend` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Depon` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Contr` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Hiat` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Mut` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Causing_Mut` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Hybrid_form` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Problematic_Form` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Onomastic_Complex` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Onomastic_Usage` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `SpecialCharacter` varchar(255) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Syntactic_ID` varchar(45) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Phrase_structure_tree` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Syntactic_Unit` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Phrase_type` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Phrase` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Syntactic_Unit_Translation` text COLLATE utf8mb4_bin NOT NULL,
  `Var_Status` varchar(255) COLLATE utf8mb4_bin DEFAULT NULL,
  `Text_ID` varchar(10) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Sort_ID` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Dumping data for table `MORPHOLOGY` (trimmed for the sga/form-lemma fixture: see README.md)
--

INSERT INTO `MORPHOLOGY` (`ID`, `Text_Unit_ID`, `Stressed_Unit`, `Morph`, `Expected_Morph`, `Lemma`, `Secondary_Meaning`, `Analysis`, `Syntactic_Context`, `Comments`, `Augm`, `Rel`, `Trans`, `Depend`, `Depon`, `Contr`, `Hiat`, `Mut`, `Causing_Mut`, `Hybrid_form`, `Problematic_Form`, `Onomastic_Complex`, `Onomastic_Usage`, `SpecialCharacter`, `Syntactic_ID`, `Phrase_structure_tree`, `Syntactic_Unit`, `Phrase_type`, `Phrase`, `Syntactic_Unit_Translation`, `Var_Status`, `Text_ID`, `Sort_ID`) VALUES
(85377, 'S0007-1', 'libardaib', 'libardaib', 'lebardaib', 'lebardae', '', 'dat.pl.neut.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 2),
(85378, 'S0007-2', 'at·tá', 'at·', 'ad·', 'ad· 1', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85378),
(85379, 'S0007-2', 'at·tá', 'at·tá', 'ad·tá', 'ad·tá', '', '3sg.pres.ind.', '', '', 'No', 'No', 'intrans.', 'deut.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85379),
(85380, 'S0007-2', 'di ṡeirc', 'di', 'di', 'di', 'at·tá + de 1: such is', 'dat.', '', 'See DIL (s.v. de 1: vol d, col 142, meaning XXVIII) for this analysis.', '', '', '', '', '', '', '', '', '+ Len.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85380),
(85381, 'S0007-2', 'di ṡeirc', 'ṡeirc', 'ṡeirc', 'serc', '', 'dat.sg.', '', '', '', '', '', '', '', '', '', '+ Len.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85381),
(85382, 'S0007-2', 'la laitnori', 'la', 'la', 'la', 'with substantive verb: at·tá y la x', 'acc.', '', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85382),
(85383, 'S0007-2', 'la laitnori', 'laitnori', 'laitneórai', 'Laitneóir', '', 'acc.pl.', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85383),
(85384, 'S0007-2', 'inna grec', 'inna', 'inna', 'in 1', '', 'gen.pl.masc.', '', '', '', '', '', '', '', '', '', '', '- Nas.', '', '', '', '', '', '', '', '', '', '', '', '', '0007', 85384),
(85385, 'S0007-2', 'inna grec', 'grec', 'gréc', 'gréc 1', '', 'gen.pl.', '', '', '', '', '', '', '', '', '', '- Nas.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85385),
(85386, 'S0007-2', 'co·seichetar', 'co·', 'co·', 'co 4', '', '', '', 'with pres ind', '', '', '', '', '', '', '', '', '- Len.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85386),
(85387, 'S0007-2', 'co·seichetar', '·seichetar', '·seichetar', 'seichithir', '', '3pl.pres.ind.', '', '', 'No', 'No', 'trans.', 'conj.', 'Yes', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85387),
(85388, 'S0007-2', 'cid a comroi[r]cniu', 'ci', 'ci', 'cía 2', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85388),
(85389, 'S0007-2', 'cid a comroi[r]cniu', 'd', 'd', 'is 1', '', '3sg.pres.subj.', '', '', 'No', 'No', 'intrans.', 'abs.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85389),
(85390, 'S0007-2', 'cid a comroi[r]cniu', 'a', 'a', '3pl.poss.pron.', '', '', '', '', '', '', '', '', '', '', '', '', '- Nas.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85390),
(85391, 'S0007-2', 'cid a comroi[r]cniu', 'comroircniu', 'comroirgnea', 'comrorgun', '', 'acc.pl.masc.', '', 'Cf. Thurn. § 736 for the masc. pl here.', '', '', '', '', '', '', '', '- Nas.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85391),
(85392, 'S0007-3', 'in méit-so', 'in', 'in', 'in 1', '', 'dat.sg.fem.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85392),
(85393, 'S0007-3', 'in méit-so', 'méit', 'méit', 'méit', 'adverbial: in méit so \'this much, this extent\'', 'dat.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85393),
(85394, 'S0007-3', 'in méit-so', 'so', 'so', '-so', '', '', '', 'after substantive preceded by article', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85394),
(85395, 'S0007-4', 'is sí', 'is', 'is', 'is 1', '', '3sg.pres.ind.', '', '', 'No', 'No', 'intrans.', 'abs.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 1),
(85396, 'S0007-4', 'is sí', 'sí', 'sí', '3sg.fem.indp.pron.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', 'MO093.1', '0007', 2),
(85397, 'S0007-4', 'tra', 'tra', 'trá', 'trá', '', '', '', 'after copula and predicate', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 3),
(85398, 'S0007-4', 'in dias-sa', 'in', 'in', 'in 1', '', 'nom.sg.fem.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 4),
(85399, 'S0007-4', 'in dias-sa', 'dias', 'diäs', 'diäs', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '- Len.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 5),
(85400, 'S0007-4', 'in dias-sa', 'sa', 'so', '-so', '', '', '', 'after substantive preceded by article', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 6),
(85401, 'S0007-4', 'ro·sechestar-som', 'ro·', 'ro·', 'ro· 2', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', 'PH023.1', '0007', 7),
(85402, 'S0007-4', 'ro·sechestar-som', 'ro·sechestar', 'ro·ṡeichestar', 'seichithir', '', 'augm.3sg.pret.', '', '', 'Yes', 'Yes', 'trans.', 'deut.', 'Yes', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 9),
(85403, 'S0007-4', 'ro·sechestar-som', 'som', 'som', 'nota augens', '', '3sg.masc.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 10),
(85404, 'S0007-5', 'i ndead', 'i', 'i', 'i', '', 'acc.', '', '', '', '', '', '', '', '', '', '', '+ Nas.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85404),
(85405, 'S0007-5', 'i ndead', 'ndead', 'deäd', 'deäd', 'with i 2 + gen: after', 'acc.sg.', '', '', '', '', '', '', '', '', '', '+ Nas.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85405),
(85406, 'S0007-5', 'inna n-í', 'inna', 'inna', 'in 1', '', 'gen.pl.masc.', 'definite_article followed by í 1', '', '', '', '', '', '', '', '', '', '+ Nas.', '', '', '', '', '', '', '', '', '', '', '', '', '0007', 85406),
(85407, 'S0007-5', 'inna n-í', 'ní', 'ní', 'í 1', '', 'gen.pl.masc.', 'definite_article + í  1 + pronoun_demonstrative', '', '', '', '', '', '', '', '', '+ Nas.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85407),
(85408, 'S0007-5', 'sin', 'sin', 'sin', 'sin', '', 'dat.sg.neut.', 'After í 1', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85408),
(85409, 'S0007-6', 'is huas neurt', 'is', 'is', 'is 1', '', '3sg.pres.ind.', '', '', 'No', 'No', 'intrans.', 'abs.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85409),
(85410, 'S0007-6', 'is huas neurt', 'huas', 'ós', 'ós 1', '', 'dat.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85410),
(85411, 'S0007-6', 'is huas neurt', 'neurt', 'neurt', 'nert', '', 'dat.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85411),
(85412, 'S0007-6', 'dom', 'dom', 'dom', 'do 1', '', '1sg.dat.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85412),
(85413, 'S0007-6', 'ara doidṅgi', 'ar', 'ar', 'ar 1', '', 'acc.', '', '', '', '', '', '', '', '', '', '', '- Len.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85413),
(85414, 'S0007-6', 'ara doidṅgi', 'a', 'a', '3sg.masc./neut.poss.pron.', '', '3sg.neut.', '', '', '', '', '', '', '', '', '', '- Len.', '- Len.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85414),
(85415, 'S0007-6', 'ara doidṅgi', 'doidṅgi', 'doidngi', 'doidnge', 'substantivized adjective', 'acc.sg.', '', 'This could also be dat sg.\r\n', '', '', '', '', '', '', '', '- Len.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85415),
(85420, 'S0007-9', 'inna flaithemnachtæ', 'inna', 'inna', 'in 1', '', 'gen.sg.fem.', '', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85420),
(85421, 'S0007-9', 'inna flaithemnachtæ', 'flaithemnachtæ', 'flaithemnachtae', 'flaithemnacht', '', 'gen.sg.', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', '', 'OR018.2', '0007', 85421),
(85428, 'S0007-11', 'inḍt airdircus', 'inḍt', 'int', 'in 1', '', 'nom.sg.masc.', '', 'GOI 294-5 §468 on errors pertaining to the alternation of the final consonant of the article.', '', '', '', '', '', '', '', '', '+ Gem.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 2),
(85429, 'S0007-11', 'inḍt airdircus', 'airdircus', 'airdaircus', 'airdaircus', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '+ Gem.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 3),
(85476, 'S0007-17', 'hí c', 'hí', 'i', 'i', '', 'dat./acc.', '', '', '', '', '', '', '', '', '', '', '- Nas.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 85476),
(91130, 'S0007-1258', 'cai', 'cai', '', 'Cai', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91130),
(91321, 'S0007-1307', 'écen', 'écen', 'éicen', 'éicen', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91321),
(91323, 'S0007-1309', 'trói', 'trói', 'Troí', 'Troí', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91323),
(91343, 'S0007-1318', 'etir aicned', 'etir', 'eter', 'eter', 'followed by two or more objj. connected by ocus', 'acc.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91343),
(91344, 'S0007-1318', 'etir aicned', 'aicned', 'aicned', 'aicned', '', 'acc.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91344),
(91345, 'S0007-1318', '7 suidigud', '7', 'ocus', 'ocus 2', '', '', 'conjoining noun phrases', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91345),
(91346, 'S0007-1318', '7 suidigud', 'suidigud', 'suidiugud', 'suidiugud', '', 'acc.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91346),
(91348, 'S0007-1320', 'cucann', 'cucann', 'cucann', 'cucann', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 91348),
(91360, 'S0007-1326', 'lasna anmmann', 'la', 'la', 'la', '', 'acc.', '', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 1),
(91361, 'S0007-1326', 'lasna anmmann', 'sna', 'sna', 'in 1', '', 'acc.pl.neut.', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 2),
(91362, 'S0007-1326', 'lasna anmmann', 'anmmann', 'anmann', 'ainm', '', 'acc.pl.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', 'MO037.1', '0007', 3),
(91363, 'S0007-1326', 'i n.is', 'i', '', 'i', '', 'dat.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 4),
(91375, 'S0007-1329', 'Ad·comlatar-sidi', 'Ad·', 'ad·', 'ad· 1', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 2),
(91376, 'S0007-1329', 'Ad·comlatar-sidi', '·com', '·com', 'con· 1', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 3),
(91377, 'S0007-1329', 'Ad·comlatar-sidi', 'ad·comlatar', 'ad·comlatar', 'ad·comla', '', '3pl.pres.ind.pass.', '', '', 'No', 'No', 'pass.', 'deut.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 4),
(91378, 'S0007-1329', 'Ad·comlatar-sidi', 'sidi', 'sidi', '-side', '', 'nom.pl.', 'subject of the verb', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 5),
(91379, 'S0007-1329', 'fri cach tuisel', 'fri', 'fri', 'fri', '', 'acc.', '', '', '', '', '', '', '', '', '', '', '- Gem.', '', '', '', '', '', '', '', '', '', '', '', 'MO081.1', '0007', 6),
(91380, 'S0007-1329', 'fri cach tuisel', 'cach', 'cach', 'cach', '', 'acc.sg.masc.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 7),
(91381, 'S0007-1329', 'fri cach tuisel', 'tuisel', 'tuisel', 'tuisel', '', 'acc.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 8),
(91382, 'S0007-1329', '7 ní·dentar', '7', 'ocus', 'ocus 2', '', '', 'conjoining clauses or sentences', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 9),
(91383, 'S0007-1329', '7 ní·dentar', 'ní·', 'ní·', 'ní 3', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 10),
(91384, 'S0007-1329', '7 ní·dentar', '·de', '·dé', 'de·, dí·', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 11),
(91385, 'S0007-1329', '7 ní·dentar', '·dentar', '·déntar', 'do·gní', '', '3sg.pres.ind.pass.', '', '', 'No', 'No', 'pass.', 'prot.', 'No', 'No', 'No', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 12),
(91386, 'S0007-1329', 'cach tuisel', 'cach', 'cach', 'cach', '', 'nom.sg.masc.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 13),
(91387, 'S0007-1329', 'cach tuisel', 'tuisel', 'tuisel', 'tuisel', '', 'nom.sg.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 14),
(91388, 'S0007-1329', 'díib', 'díib', '', 'di', '', '3pl.dat.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 15),
(121963, 'S0007-17', 'hí c', 'c', 'c', '(Latin letters and suffixes)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 121963),
(122309, 'S0007-4', 'ro·sechestar-som', '∅', '∅', 'len.rel.particle', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 8),
(132158, 'S0007-1', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 1),
(132159, 'S0007-2', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132160, 'S0007-5', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132161, 'S0007-6', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132163, 'S0007-11', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 1),
(132169, 'S0007-17', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132170, 'S0007-17', 'ut', 'ut', '', 'ut', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132171, 'S0007-17', 'accentus.', 'accentus.', '', 'accentus', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(132172, 'S0007-17', 'd', 'd', '', '(Latin letters and suffixes)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', NULL),
(133946, 'S0007-1326', 'i n.is', 'nis', '', '(Latin letters and suffixes)', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 5),
(133948, 'S0007-1329', '.i.', '.i.', '', '.i.', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', '', NULL, '0007', 1);

CREATE TABLE `SENTENCES` (
  `ID` int(11) NOT NULL,
  `Text_ID` varchar(5) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Text_Unit_ID` varchar(20) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Locus1` mediumtext COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Locus2` mediumtext COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Locus3` mediumtext COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Textual_Unit` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Translation` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Textual_Notes` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Translation_Notes` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Latin_Text` mediumtext COLLATE utf8mb4_bin NOT NULL,
  `Translation_From_Latin` text COLLATE utf8mb4_bin NOT NULL,
  `Variant_Readings` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Subunit` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Sort_ID` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Dumping data for table `SENTENCES` (trimmed for the sga/form-lemma fixture: see README.md)
--

INSERT INTO `SENTENCES` (`ID`, `Text_ID`, `Text_Unit_ID`, `Locus1`, `Locus2`, `Locus3`, `Textual_Unit`, `Translation`, `Textual_Notes`, `Translation_Notes`, `Latin_Text`, `Translation_From_Latin`, `Variant_Readings`, `Subunit`, `Sort_ID`) VALUES
(11159, '0007', 'S0007-1', 'Sg 001a01', 'Sg 001a10 e', '', '.i. libardaib', 'i.e. bookish (arts)', 'Hofman 1996, II, 5: „Caused by corrupt „libralibus“ for „liberalibus (artibus)“ (the liberal arts). Connected with „liber“ (book) by the glossator. ‘Glossator confuses „liberalis“ (liberal) with „lirarius“ (scribe)’, DIL,L,64,44, which goes back to the interpretation ‘i.e. librariis’ in Thes., cf. fn. g. But from the parallels in DIL it is clear that „lebarda“ nowhere refers to scribes.“', '', 'libralibus', '', '', '', 11159),
(11160, '0007', 'S0007-2', 'Sg 001a02', 'Sg 001a14 f', '', '(m.l.) .i. at·tá di ṡe(i)rc¹/ la laitnori inna grec co/seichetar cid a com/roicniu² [leg. comroircniu]', 'i.e. the Latin grammarians have such love for the Greeks that they follow even their errors', 'Thes. II, 49 fn c: „the second i over the line“\n² Thes. reads acomroircniu“\nHofman 1996, II, 5: „the omission of the sign for nasal mutation after the gen. pl. of the article is characteristic of the archaic layer of the gl., according to P.-Y. Lambert; comroicniu Ms., comroircniu corr. Thes., fn.e; cf. Thurn. (Gramm. 454), where Wb. 30c21 is quoted.“\nLine-break inserted.', '', 'cum omnis eloquentiae doctrinam et omne studiorum genus sapientiae luce praefulgens a Graecorum fontibus deriuatum Latinos proprio sermone inuenio celebrasse et in omnibus illorum uestigia liberalibus consecutos artibus uideo, nec solum ea, quae emendate ab illis sunt prolata, sed etiam quosdam errores eorum amore doctorum deceptos imitari, in quibus maxime uetustissima grammatica ars arguitur peccasse, cuius auctores,[…]', '', '', '', 11160),
(11161, '0007', 'S0007-3', 'Sg 001a03', 'Sg 001a17 h', '', 'in méitso', 'so much', '', '', 'tanto', '', '', '', 11161),
(11162, '0007', 'S0007-4', 'Sg 001a04', 'Sg 001a20 k', '', '(m.l.) issí tra indiassa ro·<s>echestarsom', 'it is this couple, then, that he has followed', 'Hofman 1996, II, 5: „The first s in „ro·sechestar“ is not legible anymore because of damaged parchment; tra Ms., tra Thes.“', '', '[…] quanto sunt iuniores, tanto perspicaciores, et ingeniis floruisse et diligentia ualuisse omnium iudicio confirmantur eruditissimorum (quid enim Herodiani artibus certius, quid Apollonii scrupulosis quaestionibus enucleatius possit inueniri?) cum igitur eos omnia fere uitia, […]', '', '', '', 11162),
(11163, '0007', 'S0007-5', 'Sg 001a05', 'Sg 001a29 n', '', '.i. indead innanísin', 'i.e. after them', '', '', 'post illos', '', '', '', 11163),
(11164, '0007', 'S0007-6', 'Sg 001a06', 'Sg 001a33 o', '', '.i. is huas neurt dom ara doidṅgi', 'i.e. it is above my strength for its difficulty', '', '', '[…] sed non impudenter, ut puto, conatus sum (pro) uiribus rem arduam quidem, sed officio professionis non indebitam, supra nominatorum praecepta uirorum, quae congrua sunt uisa, in Latinum transferre sermonem, collectis etiam omnibus fere […]', '', '', '', 11164),
(11167, '0007', 'S0007-9', 'Sg 002a01', 'Sg 002a01 a', '', 'innaflaithemnachtæ', 'of the rule', '', 'Hofman vol. 2, p. 7: „‘Princedom’ Thes., 3 inst. in DIL, F,161,66-9, < „flaithem“ (ruler, prince). ‘Rule’ is better than ‘princedom’ here, as P. calls Iulianus „consul ac patricius“ only in 2,25 (cf. gl. o) and 195,2.“', 'huius tamen operis te hortatorem sortitus iudicem quoque facio,Iuliane consul ac patricie, cui summos [dignita]tis gradus summa adquisiuit in omni studio ingenii claritudo […]', '', '', '', 11167),
(11169, '0007', 'S0007-11', 'Sg 002a03', 'Sg 002a02 c', '', '.i. inḍt airdircus', 'i.e. the conspicuousness', '', '', 'huius tamen operis te hortatorem sortitus iudicem quoque facio,Iuliane consul ac patricie, cui summos dignitatis gradus summa adquisiuit in omni studio ingenii claritudo, […]', '', '', '', 11169),
(11175, '0007', 'S0007-17', 'Sg 002a09', 'Sg 002a23 u', '', '.i. ut accentus. d hí c', 'i.e. as [=ad-cantus] d into c', 'Hofman 1996, II, 8: „Refers to the assimilation d > c, „ad-cantus > accentus“. The ex. in 35,1, „d transit in c, ut accidit“, is different.“', '', '[…] quae in quas transeunt per declinationes uel compositiones partium orationis.', '', '', '', 11175),
(12416, '0007', 'S0007-1258', 'Sg 050', '050 m.i. ss', '', '(m.i.) feria cai hodie (scriptura ogamica)', '', '', '', '', '', '', '', 12416),
(12465, '0007', 'S0007-1307', 'Sg 051a01', 'Sg 051a08“ b', '', 'écen', 'violence', '', '', 'uiolentus uiolenti +uiolentĭa', '', '', '', 12465),
(12467, '0007', 'S0007-1309', 'Sg 051a03', 'Sg 051a11“ f', '', 'trói', 'Troy', '', '', 'Teucrus uel Teucer Teucri Teucria.', '', '', '', 12467),
(12476, '0007', 'S0007-1318', 'Sg 051b02', 'Sg 051b09 b', '', 'etir aicned 7 suidigud', 'both by nature and position', '', '', 'na uero desinentia denominatiua siue uerbalia, de quibus iam diximus, cum de possessiuis nus uel na uel num desinentibus tractabamus, omnimodo longam habent paenultimam uel natura uel positione: officium officīna, medicus medicīna, rex regis regīna, leo leaēna, doctrix doctrīna, tonstrix tonstrīna, cocus cocīna et culīna, cantus cantilēna, far farīna, luceo lucērna, lux Lucīna, lateo latērna.', '', '', '', 12476),
(12478, '0007', 'S0007-1320', 'Sg 051b04', 'Sg 051b22“ d', '', 'cucann', 'kitchen', '', '', 'cocus cocīna et culīna', '', '', '', 12478),
(12484, '0007', 'S0007-1326', 'Sg 051b10', 'Sg 051b33“ s', '', 'lasna anmmann. in .is', 'with the nouns <ending> in „-is“', '', '', 'in e desinentia deriuatiua neutra sunt, ut sedile, monile, cubile, utile, et quia pleraque a communibus in is terminantibus nascuntur, melius (cum) illis tractabuntur.', '', '', '', 12484),
(12487, '0007', 'S0007-1329', 'Sg 051b13', 'Sg 051b42“ y', '', '.i. Ad·comlatarsidi fri cach tuisel 7 ní·dentar cach tuisel díib .,', 'i.e. these are joined to every case, and every case is not made of them', '', '', 'quidam enim figurate frugi datiuum et nihili genetiuum, ut ante dictum est, cum aliis omnibus coniungi casibus non irrationabiliter dicunt, sicut mancipi et nec mancipi et cordi et huiusmodi et illiusmodi et similia.', '', '', '', 12487);

CREATE TABLE `TEXT` (
  `ID` int(11) NOT NULL,
  `Text_ID` varchar(10) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Title` varchar(100) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Date` varchar(200) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Dating_Criteria` varchar(1000) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Edition` varchar(500) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `MSS` varchar(500) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Digital_MSS` varchar(200) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Thes` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Contributor` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Created_Date` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `MS_Checked` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Reason_Of_MS_Choice_And_Editorial_Policy` varchar(50) COLLATE utf8mb4_bin NOT NULL DEFAULT '',
  `Reference` text COLLATE utf8mb4_bin NOT NULL,
  `Sort_ID` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_bin;

-- Dumping data for table `TEXT` (trimmed for the sga/form-lemma fixture: see README.md)
--

INSERT INTO `TEXT` (`ID`, `Text_ID`, `Title`, `Date`, `Dating_Criteria`, `Edition`, `MSS`, `Digital_MSS`, `Thes`, `Contributor`, `Created_Date`, `MS_Checked`, `Reason_Of_MS_Choice_And_Editorial_Policy`, `Reference`, `Sort_ID`) VALUES
(7, '0007', 'St_Gall_Priscian', 'MS: 850-851, date range 825-851 is used for the text in ChronHib.', 'Ó Néill, 2000 based on the observance of Lents dates the writing of the MS to between Oct. 850 to August 851. See the document on dating criteria for discussion on the date(s) of the glosses.', 'Bauer 2015a;\nThes. II, 49–224', 'St. Gall, Stiftsbibliothek, Cod. Sang. 904', 'https://www.e-codices.unifr.ch/en/list/one/csg/0904', 'ii. 49–224', 'Bernhard Bauer', 'previous', 'Yes', '', 'Bauer 2015b', 7);

