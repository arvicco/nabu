The file "kranten_pd_16xx.zip" contains full texts (OCR, ALTO, XML) of 8.559 newspaper editions from the 17th century, from 14-06-1618 up to and including 31-12-1699

Permantent URL of this zipfile : http://resolver.kb.nl/resolve?urn=DATA:kranten:kranten_pd_16xx.zip

=== Delpher open newspaper archive ===
This zipfile is part of the Delpher open newspaper archive. To find out about this archive and the zipfiles it contains, visit http:///www.delpher.nl/data (choose "Download teksten als zip-bestanden --> Delpher open krantenarchief"). Please note: this information is available in Dutch only for the time being, but Delpher is working on providing these pages in English a.s.a.p.

=== Terms of use & citation === 
The Delpher open newspaper archive has been released under the CC-BY 4.0 license. See https://creativecommons.org/licenses/by/4.0/ . If you want to reuse the archive as a whole, or substantial parts of it, you must therefore explicitly mention the license and attribution. You do this as follows:

"Delpher open newspaper archive (1.0), Creative Commons Attribution 4.0, The Hague, 2017 - https://creativecommons.org/licenses/by/4.0/"

Please note: The texts (OCR, ALTO) of individual newspapers editions and articles are in the public domain, free of copyrights. 

=== Exploring the data ===
* The newspaper editions contained in this zipfile can be explored 'live' on Delpher via : http://www.delpher.nl/nl/kranten/results?query=&page=1&sortfield=date&cql%5B%5D=(date+_gte_+%2201-01-1618%22)&cql%5B%5D=(date+_lte_+%2231-12-1699%22)&coll=dddtitel 
Please note: the newspaper zip archive is updated less frequently than Delpher. The data in this zipfile might therefore be out of sync (ie. behind) with that in Delpher. 

* The file "index_kranten_pd_16xx.tsv" contains the exact titles, dates of publication and identifiers of the 8.559 newspaper editions in this zipfile 
(tsv = tab seperated value).

===Structure of zipfile ===
The newspapers in the file "kranten_pd_16xx.zip" are organised in a tree structure:
 * Folder per year 1618-1699 
 * * Folder per month (based on month numbers, 01=January, 12=December)
 * * * Folder per day (based on day numbers)
 * * * * Folder based on a unique identifier, commonly starting with "DDD_ddd_" or "KRANTEN_MMKB". In the file "index_kranten_pd_16xx.tsv" you will find which newspaper title and date corresponds to which unique identifier. In the folder you will find: 
 * * * * * Metadata coded into a MPEG21-DIDL file, per newspaper edition (didl.xml)
 * * * * * Text coded into (uncorrected) OCR files, per newspaper article (file name ends with _articletext.xml). 
 * * * * * Word coordinates coded into ALTO files, per newspaper page (file name ends with _alto.xml). 

To keep its download size manageable this zipfile does NOT contain the newspaper page scans (JP2 files) and editions in PDF format you can find on the Delpher site. The metadata (didl.xml) contains persistent URLs of the JP2 files (syntax: http://resolver.kb.nl/resolve?urn=<identifier>:<pagenumber>:image) and PDF files (syntax: http://resolver.kb.nl/resolve?urn=<identifier>:pdf). From these URLs you can download the files yourself.

=== Questions, remarks, suggestions? ===  
Delpher would like to hear them via dataservices@kb.nl

Last update:13-01-2017