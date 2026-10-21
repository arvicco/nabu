---
license: cc-by-4.0
---
# Oracle Bone Inscriptions Multi-modal Dataset (OBIMD)

## Dataset Overview

The Oracle Bone Inscriptions Multi-modal Dataset (OBIMD) is the first large-scale corpus providing pixel-aligned rubbings and facsimiles, character-level annotations, and sentence-level transcriptions and reading sequences for oracle bone inscription (OBI) research. This dataset enables multi-modal learning across visual, structural, and linguistic dimensions, laying the foundation for end-to-end OBI recognition and interpretation.
<p align="center">
<img src="figures/overview.png" alt="图片" width="80%" height="80%">
</p>


## Dataset Statistics

- Total OBI images: 10,077 across five Shang Dynasty phases
- Annotated characters: 93,652
- Missing character positions: 21,667 (due to fragmentation)
- Sentences: 21,941 syntactically validated
- Non-sentential elements: 4,192

## Data Structure

The dataset follows a three-level hierarchy:

1. Image-level: Contains rubbing and facsimile pairs
2. Sentence-level: Groups characters into meaningful units
3. Character-level: Detailed annotations for each character
![图片](figures/data%20structure.png)

## Data Fields

|Field Name|Description|Example|
|-|-|-|
|Facsimile|Path to facsimile image|facsimile/h00002.jpg|
|Rubbing|Path to rubbing image|rubbing/h00002.jpg|
|RubbingName|Short identifier|H2|
|GroupCategory|Sentence type|InscriptionSentence1|
|Position|Bounding box (x,y,w,h)|558,581,80,218| 
|OrderNumber|Character order in sentence|5|
|Label|Main character label|xkubtjk815|
|SubLabel|Secondary label|xkubtjk815|
|SeatFont|Placeholder indicator|0|
|Mark|Special marker|-1|

## Data Modalities

1. Rubbing images: Original scanned images of oracle bones
2. Facsimile images: Expert reconstructions aligned with rubbings
3. Character annotations: Bounding boxes and classifications
4. Sentence groupings: Semantic organization of characters
5. Reading sequences: Order of characters within sentences
![图片](figures/pipeline%20for%20constructing.png)

## Hierarchical Character Metadata Supplement

This folder contains supporting materials for the character hierarchy used in OBIMD. It includes:

1. Sub-character Images: Images of sub-character variants, stored in a two-level folder structure. The top-level directory is named by the main character UID, and each subfolder is named by the corresponding sub-character UID.
2. Sub-character to Glyph Code Point Mapping (XLSX): Maps each sub-character UID to the platform-specific glyph code point used by the Oracular Digital Platform font.
3. Sub-character to Main-character Mapping (XLSX): Maps each sub-character UID to its parent main character UID in the Oracular Digital Platform.
4. Main-character → Reference Modern Character (JSON): For each main-character UID, the JSON provides a platform-provided reference modern Chinese character (a standardized surrogate used for lookup and navigation). Note: this mapping is for reference only and is not intended as a final philological interpretation, since oracle bone inscriptions decipherment remains ongoing.

## Usage Notes

The dataset is designed to support various research tasks:

- Character detection and recognition
- Sentence-level character clustering
- Character reordering within sentences
- Multi-modal analysis (rubbing vs. facsimile)

## License

This model is licensed under CC-BY 4.0.

## Citation

If you use this dataset in your research, please cite:

<!-- ```bibtex
@article{li2024obimd,
  title={Oracle Bone Inscriptions Multi-modal Dataset},
  author={Li, Bang and Luo, Donghao and Liang, Yujie and others},
  journal={arXiv preprint arXiv:2407.03900},
  year={2024},
  url={https://doi.org/10.48550/arXiv.2407.03900}
}
```
## License
The dataset is released for academic research purposes only. Commercial use requires special permission from the authors. -->
