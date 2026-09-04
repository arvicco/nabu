-- TGAZ 2018 dump, TRIMMED fixture (see README.md)
CREATE TABLE `mv_pn_srch` (
  `id` int(10) unsigned NOT NULL DEFAULT '0',
  `sys_id` varchar(30) NOT NULL,
  `data_src` varchar(10) NOT NULL,
  `name` varchar(256),
  `transcription` varchar(256),
  `beg_yr` int(11) DEFAULT NULL,
  `end_yr` int(11) DEFAULT NULL,
  `obj_type` enum('POINT','POLYGON','LINE','ENTITY') DEFAULT NULL,
  `x_coord` varchar(30) DEFAULT NULL,
  `y_coord` varchar(30) DEFAULT NULL,
  `ftype_vn` varchar(100) DEFAULT NULL,
  `ftype_tr` varchar(100) DEFAULT NULL,
  `parent_id` int(10) unsigned DEFAULT NULL,
  `parent_sys_id` varchar(30),
  `parent_vn` varchar(256),
  `parent_tr` varchar(256),
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

INSERT INTO `mv_pn_srch` VALUES (1,'hvd_1','CHGIS','霸州','Ba Zhou',1820,1820,'POINT','116.39525','39.10154','州','zhou',2003,'hvd_9513','顺天府','Shuntian Fu'),(2,'hvd_2','CHGIS','正黄等四旗牧厂','Zhenghuangdengsiqi Muchang',1820,1820,'POINT','113.89422','41.21478','牧场','mu chang',1948,'hvd_2065','口北三厅','Koubeisanting'),(3,'hvd_3','CHGIS','定兴县','Dingxing',1820,1820,'POINT','115.77419','39.26959','县','xian',1996,'hvd_9506','保定府','Baoding Fu'),(4,'hvd_4','CHGIS','深泽县','Shenze',1820,1820,'POINT','115.19209','38.18490','县','xian',1990,'hvd_9500','定州','Ding Zhou'),(5,'hvd_5','CHGIS','曲阳县','Quyang',1820,1820,'POINT','114.69020','38.62145','县','xian',1990,'hvd_9500','定州','Ding Zhou'),(6,'hvd_6','CHGIS','枣强县','Zaoqiang',1820,1820,'POINT','115.71808','37.50264','县','xian',1991,'hvd_9501','冀州','Ji Zhou'),(7,'hvd_7','CHGIS','武邑县','Wuyi',1820,1820,'POINT','115.89066','37.80599','县','xian',1991,'hvd_9501','冀州','Ji Zhou'),(8,'hvd_8','CHGIS','南宫县','Nangong',1820,1820,'POINT','115.38007','37.35915','县','xian',1991,'hvd_9501','冀州','Ji Zhou'),(9,'hvd_9','CHGIS','衡水县','Hengshui',1820,1820,'POINT','115.70573','37.72616','县','xian',1991,'hvd_9501','冀州','Ji Zhou'),(10,'hvd_10','CHGIS','新河县','Xinhe',1820,1820,'POINT','115.24651','37.52959','县','xian',1991,'hvd_9501','冀州','Ji Zhou');
