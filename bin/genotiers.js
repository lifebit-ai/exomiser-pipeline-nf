const mongoose = require('mongoose');

const genotiersSchema = new mongoose.Schema({
  acmgAppxScore: {
    type: Number
  },
  acmgBenignSubscore: {
    type: String
  },
  acmgCodingImpact: {
    type: String
  },
  acmgGeneId: {
    type: Number
  },
  acmgPathogenicSubscore: {
    type: String
  },
  acmgUserExplain: {
    type: Array
  },
  acmgVerdict: {
    type: String
  },
  acmgVersion: {
    type: String
  },
  allelicBalance: {
    type: Number
  },
  alternative: {
    type: String
  },
  all1: {
    type: String
  },
  all2: {
    type: String
  },
  ampApproxScore: {
    type: String
  },
  ampClassifications: {
    type: String
  },
  ampClassificationsTier: {
    type: String
  },
  ampName: {
    type: String
  },
  ampTier1: {
    type: String
  },
  ampTier2: {
    type: String
  },
  ampTier3: {
    type: String
  },
  ampTier4: {
    type: String
  },
  ampVerdict: {
    type: String
  },
  ampVerdictTier: {
    type: String
  },
  ampVersion: {
    type: String
  },
  cbio: {
    type: String
  },
  chromosome: {
    type: String,
    required: true
  },
  coverage: {
    type: Number
  },
  fullLocation: {
    type: String,
    required: true
  },
  gene: {
    type: String
  },
  genotype: {
    type: String
  },
  i: {
    type: String,
    required: true
  },
  location: {
    type: String,
    required: true
  },
  notes: {
    type: String
  },
  position: {
    type: Number,
    required: true
  },
  reference: {
    type: String
  },
  barcode: {
    type: String
  },
  variantType: {
    type: String
  },
  vcfSampleId: {
    type: String
  },
  zygosity: {
    type: String
  },
  exomiserQual: {
    type: String
  },
  exomiserFilter: {
    type: String
  },
  exomiserGenotype: {
    type: String
  },
  exomiserHgvs: {
    type: String
  },
  exomiserCoverage: {
    type: String
  },
  exomiserFunctionalClass: {
    type: String
  },
  exomiserVariantScore: {
    type: String
  },
  exomiserGene: {
    type: String
  },
  exomiserGenePhenoScore: {
    type: String
  },
  exomiserGeneVariantScore: {
    type: String
  },
  exomiserGeneCombinedScore: {
    type: String
  },
  exomiserCadd: {
    type: String
  },
  exomiserPolyphen: {
    type: String
  },
  exomiserMutationTaster: {
    type: String
  },
  exomiserSift: {
    type: String
  },
  exomiserRemm: {
    type: String
  },
  exomiserDbsnp: {
    type: String
  },
  exomiserMaxFreq: {
    type: String
  },
  exomiserDbsnpFreq: {
    type: String
  },
  exomiserEvsEaFreq: {
    type: String
  },
  exomiserEvsAaFreq: {
    type: String
  },
  exomiserExacAfrFreq: {
    type: String
  },
  exomiserExacAmrFreq: {
    type: String
  },
  exomiserExacEasFreq: {
    type: String
  },
  exomiserExacFinFreq: {
    type: String
  },
  exomiserExacNfeFreq: {
    type: String
  },
  exomiserExacSasFreq: {
    type: String
  },
  exomiserExacOthFreq: {
    type: String
  },
  exomiserContributingVariant: {
    type: String
  }
})

genotiersSchema.index({fullLocation: 1, i: 1 }, { unique: true })
mongoose.model('Genotiers', genotiersSchema, 'genotiers');