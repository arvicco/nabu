# PNA Network
The data used for creating "A Social Network of the Prosopography of the Neo-Assyrian Empire"

The networks were created from the text and pdf file versions of the Prosopography of the Neo-Assyrian Empire (PNA). There are two different networks created from the same data. In the two-mode network, persons are connected to the texts in which they are attested. The one-mode network connects two persons if they are attested in the same document. A short explanation of the procedure of creating the networks is below.

In order to study and visualize the networks, it is sufficient to download the file Networks.zip. The files in SupplementaryData.zip contain more in-depth explanations of the procedure of creating the networks, the normalization lists used for that, and the output of different stages of the procedure.

For the reasons of copyright, we are not able to publish the data from which the networks have been extracted. But we hope that by publishing all the source codes, concordance lists, and outputs with explanations, we give the user a picture of how the networks were created.


PNA = Radner, K., & Baker, H. D. (Eds.). (1998–2011). The Prosopography of the Neo-Assyrian Empire. Helsinki: The Neo-Assyrian Text Corpus Project.


### Contents of the repository

Networks: The networks as csv files and a gephi project that can be used for studying and visualizing the networks

SupplementaryData
* DocumentNameExtraction: The document name extraction from the text files
* Lists: Various lists used for extracting the names of documents and individuals and for creating the network
* NetworkCreation: The creation of the networks and writing csv files
* Output: Lists produced during the various stages of creating the network
* PersonExtractionPdfFile: The process of finding individuals and documents in the pdf file
* PersonExtractionTextFiles: The process of finding individuals and documents in the text files


### A short explanation of the workflow
* Getting document names from the PNA text files provided by Simo Parpola (Editor in Chief of PNA)
	* the document names are indicated by '@@' 
  * Various lists of concordances to standardize the document names were used
  * Each document name with the original line it was found in was saved for use in later steps
  * See the folder DocumentNameExtraction for more details
* Finding names and other info of individuals in the text files
	* Names are indicated with '*' before them and individuals with the same name have been numbered
		* Individuals were given the number in PNA or 1 if only one individual has the specific name
		* The number was added to the name with underscore, e.g. Aššūr-iddin_1
	* The general description and dating of each individual as well as the language and gender of the name were also extracted
  * The documents in which an individual is mentioned were extracted by using the "original line - standardized name" conversion list produced in the previous step
  * See the folder PersonExtractionTextFiles for more details
* Finding names and other info of individuals in the text file extracted from PNA_3_2.pdf
	* As preprocessing, the pdf-file was copied to Word and then turned into a text file and semimanually curated
		* Names of individuals that in the pdf-file were marked with bold, were in Word marked with '*'
		* Mistakes caused by copying from two-columns to one were corrected by hand
	* Individuals with the same name have been numbered and now names were indicated with '*' before them 
		* Individuals are given the number used in PNA or 1 if only one individual has the specific name
		* The number is added to the name with underscore
	* The general description and dating of each individual as well as the language and gender of the name were also extracted 
	* Document names were found in the unstructured running text by using the list of document names in the text files + concordance lists
	* See the folder PersonExtractionPdfFile for more details
* Building a two-mode network of individuals and the documents they are attested in and a one-mode co-occurrence network of people attested in the same document
	* For the one-mode network, shorter/standardized versions of the language of a name, date, profession, ethnicity, and place were produced using various normalization lists (see folder Lists)
	* Writing csv files (a = two-mode network, b and c together form the one-mode network)
		1. of individuals and the documents they are attested in
		2. of individuals with their metadata
		3. of connections between the individuals in 2., the connections come from appearing in same documents
	* See the folder NetworkCreation for more details


### Dataset creators
* Heidi Jauhiainen (University of Helsinki) was responsible for research design, data extraction and validation, dataset creation, and software development. 
* Tero Alstola (University of Helsinki) was responsible for research design, validation, and Assyriological research. 
* Saana Svärd (University of Helsinki) was responsible for conceptualization and funding acquisition. 
* Krister Lindén (University of Helsinki) was responsible for conceptualization and methodology. 
* Repekka Uotila (University of Helsinki) worked on normalization and reference lists.



### Acknowledgements

We gratefully acknowledge the work of our colleagues who have created The Prosopography of the Neo-Assyrian Empire. The PNA volumes were edited by Heather D. Baker and Karen Radner in the context of the Neo-Assyrian Text Corpus Project (PI Simo Parpola). Baker’s later work on PNA was carried out in the framework of the Royal Institutional Households in First Millennium BC Mesopotamia project, funded by the Austrian Science Fund (FWF). The individual entries in the prosopography were written by colleagues who are too many to be listed here. We thank Parpola for making the PNA volumes available to us in plain text and pdf formats, and Baker, Parpola, and Radner for the permission to publish the dataset online. Some metadata on the attestations of Assyrian kings was collected from the State Archives of Assyria Online, a part of the Munich Open-access Cuneiform Corpus Initiative (PIs Karen Radner and Jamie Novotny, LMU Munich). We also thank the members of the Centre of Excellence in Ancient Near Eastern Empires and the participants of several workshops for their helpful feedback on various versions of the dataset.


These files are licensed under a Creative Commons Attribution-ShareAlike 3.0 Unported License.
