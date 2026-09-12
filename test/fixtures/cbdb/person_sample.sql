-- CBDB person-index fixture (see README.md) — REAL rows from
-- cbdb_20260905.sqlite3, schemas verbatim, three persons + altnames + dynasty.
CREATE TABLE "BIOG_MAIN" (
    "c_personid" INTEGER(11) NOT NULL,
    "c_name" varchar(255) DEFAULT NULL /* Hanyu Pinyin full name; auto-generated: c_surname + " " + c_mingzi */,
    "c_name_chn" varchar(255) DEFAULT NULL /* Chinese full name; auto-generated: c_surname_chn + c_mingzi_chn (no space) */,
    "c_index_year" smallint(6) DEFAULT NULL,
    "c_index_year_type_code" varchar(255) DEFAULT NULL,
    "c_index_year_source_id" INTEGER(11) DEFAULT NULL,
    "c_female" smallint(6) DEFAULT NULL,
    "c_index_addr_id" INTEGER(11) DEFAULT 0,
    "c_index_addr_type_code" smallint(6) DEFAULT NULL,
    "c_ethnicity_code" smallint(6) DEFAULT NULL,
    "c_household_status_code" smallint(6) DEFAULT NULL,
    "c_tribe" varchar(255) DEFAULT NULL,
    "c_birthyear" smallint(6) DEFAULT NULL,
    "c_by_nh_code" smallint(6) DEFAULT NULL,
    "c_by_nh_year" smallint(6) DEFAULT NULL,
    "c_by_range" smallint(6) DEFAULT NULL,
    "c_deathyear" smallint(6) DEFAULT NULL,
    "c_dy_nh_code" smallint(6) DEFAULT NULL,
    "c_dy_nh_year" smallint(6) DEFAULT NULL,
    "c_dy_range" smallint(6) DEFAULT NULL,
    "c_death_age" smallint(6) DEFAULT NULL,
    "c_death_age_range" smallint(6) DEFAULT NULL,
    "c_fl_earliest_year" smallint(6) DEFAULT NULL,
    "c_fl_ey_nh_code" smallint(6) DEFAULT NULL,
    "c_fl_ey_nh_year" smallint(6) DEFAULT NULL,
    "c_fl_ey_notes" TEXT DEFAULT NULL,
    "c_fl_latest_year" smallint(6) DEFAULT NULL,
    "c_fl_ly_nh_code" smallint(6) DEFAULT NULL,
    "c_fl_ly_nh_year" smallint(6) DEFAULT NULL,
    "c_fl_ly_notes" TEXT DEFAULT NULL,
    "c_surname" varchar(255) DEFAULT NULL /* Hanyu Pinyin romanization of the person's surname; auto-generated from c_surname_chn via pinyin lookup table */,
    "c_surname_chn" varchar(255) DEFAULT NULL /* Chinese surname; split from c_name_chn by matching longest known surname in pinyin table */,
    "c_mingzi" varchar(255) DEFAULT NULL /* Hanyu Pinyin romanization of the person's given name (excluding surname); auto-generated from c_mingzi_chn */,
    "c_mingzi_chn" varchar(255) DEFAULT NULL /* Chinese given name (excluding surname); remainder of c_name_chn after surname extraction */,
    "c_dy" smallint(6) DEFAULT NULL,
    "c_choronym_code" smallint(6) DEFAULT NULL,
    "c_notes" TEXT DEFAULT NULL,
    "c_by_intercalary" smallint(6) DEFAULT NULL,
    "c_dy_intercalary" smallint(6) DEFAULT NULL,
    "c_by_month" smallint(6) DEFAULT NULL,
    "c_dy_month" smallint(6) DEFAULT NULL,
    "c_by_day" smallint(6) DEFAULT NULL,
    "c_dy_day" smallint(6) DEFAULT NULL,
    "c_by_day_gz" smallint(6) DEFAULT NULL,
    "c_dy_day_gz" smallint(6) DEFAULT NULL,
    "c_surname_proper" varchar(255) DEFAULT NULL /* Surname in the person's native language (non-Chinese), if applicable; user-editable */,
    "c_mingzi_proper" varchar(255) DEFAULT NULL /* Given name in the person's native language (non-Chinese, excluding surname), if applicable; user-editable */,
    "c_name_proper" varchar(255) DEFAULT NULL /* Full name in the person's native language; auto-generated: c_mingzi_proper + " " + c_surname_proper (given-name-first order) */,
    "c_surname_rm" varchar(255) DEFAULT NULL /* Non-Pinyin romanization of the person's surname (e.g. Wade-Giles, McCune-Reischauer), if applicable; user-editable */,
    "c_mingzi_rm" varchar(255) DEFAULT NULL /* Non-Pinyin romanization of the person's given name (excluding surname), if applicable; user-editable */,
    "c_name_rm" varchar(255) DEFAULT NULL /* Non-Pinyin romanized full name; auto-generated: c_mingzi_rm + " " + c_surname_rm (given-name-first order) */,
    "c_created_by" varchar(255) DEFAULT NULL,
    "c_modified_by" varchar(255) DEFAULT NULL,
    "c_created_date" TEXT DEFAULT NULL,
    "c_modified_date" TEXT DEFAULT NULL,
    PRIMARY KEY ("c_personid")
);
CREATE TABLE "ALTNAME_DATA" (
    "c_personid" INTEGER(11) NOT NULL,
    "c_alt_name" varchar(255) DEFAULT NULL,
    "c_alt_name_chn" varchar(255) NOT NULL,
    "c_alt_name_type_code" smallint(6) NOT NULL,
    "c_sequence" smallint(6) DEFAULT 0,
    "c_source" INTEGER(11) DEFAULT NULL,
    "c_pages" varchar(255) DEFAULT NULL,
    "c_notes" TEXT DEFAULT NULL,
    "c_created_by" varchar(255) DEFAULT NULL,
    "c_modified_by" varchar(255) DEFAULT NULL,
    "c_created_date" TEXT DEFAULT NULL,
    "c_modified_date" TEXT DEFAULT NULL,
    PRIMARY KEY ("c_alt_name_chn", "c_alt_name_type_code", "c_personid")
);
CREATE TABLE "DYNASTIES" (
    "c_dy" smallint(6) NOT NULL,
    "c_dynasty" varchar(255) DEFAULT NULL,
    "c_dynasty_chn" varchar(255) DEFAULT NULL,
    "c_start" smallint(6) NOT NULL DEFAULT 0,
    "c_end" smallint(6) NOT NULL DEFAULT 0,
    "c_sort" smallint(6) DEFAULT NULL,
    PRIMARY KEY ("c_dy")
);
INSERT INTO BIOG_MAIN VALUES (1762, 'Wang Anshi', '王安石', 1021, '01', NULL, 0, 100513, 1, 0, 0, NULL, 1021, 516, 5, NULL, 1086, 530, 1, NULL, 66, NULL, NULL, 0, NULL, NULL, NULL, 0, NULL, NULL, 'Wang', '王', 'Anshi', '安石', 15, 20, 'Wang(2) Anshi [1762] Yi(3)''s [7082] son, Guan(1)''s [1841] grandnephew, Anguo''s [7076], Anli''s [1760], and Anshang''s [1761] brother, Fang''s [1803] uncle, Jue(1)''s [1796] great grandfather, Zhu(1) Mingzhi''s [526] and Shen(2) Jichang''s [1445] brother-in-law, Cai(1) Bian''s [8131] father-in-law and uncle-in-law, and Wu(3) Anchi''s [1957] father-in-law. Anshi was Zhang(1) Jifu''s [195], Xu(3) Xi''s [753] and Yang(2) Wei''s [2032] patron, Li(2) Ding(1)''s [1097] patron and teacher, Gong(2) Yuan'' s [941] teacher, and the teacher of Wang(2) Pin''s [7381] uncle, Boqi [3970]. He was the grandnephew of Wang(2) Guanzhi [3965], the father-in-law of Zhou(1) Jiazheng''s [480] son, Yanxian [3250]. His mother was Wu(3) Shi and his wife was Wu(3) Shi. He once arranged for a marriage between his wife''s younger sister and Wang(2) Ling [3967] whose scholarship he admired. The sister''s, and therefore Wang Anshi''s wife''s, grandfather, Wu(3) Min [4017], had the same generational name and address as Anshi''s maternal grandfather, Wu(3) Tian [7396], so that it can be assumed that they were brothers or cousins. When Wang Anshi composed the funerary inscription for the two women''s father, Wu(3) Ben [4020], in 1054, neither daughter was married. Wang(2) Ling died in 1059 at the age of 28. Wang Anshi was 32 in 1054. Wang(2) Ling was Wu(3) Yue''s [1992] maternal grandfather. The mother of Yan(5) Shu''s [2073] grandnephew, Fang [4118], was the younger sister of Wang(2) Anshi''s wife, Wu(2) Shi. Songshi yi, 5.5b discusses the coalitional significance of the fact that Lu(9) Jiawen''s [1294] son married the daughter of Wang Anshi''s son, Pang(a) [3968], and that Cai(1) Bian [8131] married Pang''s elder sister. Anshi was a friend of Wang(2) Ping''s [1856] son, Hui [3958] and his older and younger brothers were tongnianyou with the sons of Chen(1) Jiansu [7101]. XCB, 177.2a, 179.3a, 184.15a, 188.8a, 189.3a, 18a, 191.9a-10a, 192.4a-4b, 7a; XCBSB, 4.4b, 15.17a, 16.14b; Shen Gou, WJ, 2.48b; SHY:ZG, 5.1a; Zeng Gong, WJ, 45.4b; Du Dagui, ''xia,'' 14.1a; Wang Anshi, WJ, 97.998, 98.1012; Wang Ling, WJ, ''fu,'' 13b. CBD, 1, 277-281.From Hartwell''s ACTIVITY table:1075:  Working on the railroad all the time all the time all the time', 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'TTS', 'BDQKH', '2007-03-12 00:00:00', '2008-11-15 00:00:00');
INSERT INTO BIOG_MAIN VALUES (3767, 'Su Shi', '蘇軾', 1036, '01', NULL, 0, 13305, 1, 0, 0, NULL, 1036, 520, 3, NULL, 1101, 533, 1, NULL, 66, NULL, NULL, 0, NULL, NULL, NULL, 0, NULL, NULL, 'Su', '蘇', 'Shi', '軾', 15, 28, 'Su(1) Shi [3767] Posthumously purged as Yuanyou coalition member. He was Wang(2) Fang(2)''s [19172] son-in-law (twice: sororate). Su Zhe, WJ, ''houji,'' 22.1a-11a; Su Shi, WJ, ''qianji,'' 37.452 (wife #1, born Wang, who married him at age 16 and died in 1065 at age 27 after having given birth to Shi''s son #1, Mai [her sister was wife #2, who died in 1093 at age 46]). CBD, 5, 4312-24.', 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, 'TTS', 'TTS', '2007-03-12 00:00:00', '2013-05-13 00:00:00');
INSERT INTO BIOG_MAIN VALUES (38653, 'Wu Shi (Wife of Wang Anshi )', '吳氏(王安石妻)', 1024, '03', 1762, 1, NULL, NULL, 0, 0, NULL, 0, 0, 0, NULL, 0, 0, 0, NULL, NULL, 0, 0, 0, 0, NULL, 0, 0, 0, NULL, 'Wu', '吳', 'Shi (Wife of Wang Anshi )', '氏(王安石妻)', 15, 0, '', 0, 0, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, ' ', NULL, NULL, ' ', 'TTS', 'Hongsu Wang', '2007-03-12 00:00:00', '2022-08-18 00:00:00');
INSERT INTO ALTNAME_DATA VALUES (1762, 'Jiefu', '介甫', 4, NULL, 7596, '1536', NULL, 'TTS', 'BDFXL', '2007-03-12 00:00:00', '2011-08-15 00:00:00');
INSERT INTO ALTNAME_DATA VALUES (1762, 'Banshan laoren', '半山老人', 5, NULL, 7596, '1536', NULL, 'TTS', NULL, '2007-03-12 00:00:00', NULL);
INSERT INTO ALTNAME_DATA VALUES (1762, 'Wang Jinggong', '王荊公', 8, NULL, NULL, NULL, NULL, 'HUCH', 'Hongsu Wang', '2013-11-08 00:00:00', '2024-11-14 00:00:00');
INSERT INTO DYNASTIES VALUES (15, 'Song', '宋', 960, 1279, 67);
