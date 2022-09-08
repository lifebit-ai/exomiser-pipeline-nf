// ADD EXOMISER FIELDS TO GENOTIERS
// takes a TSV file, extracts `fullLocation` (i.e takes `#CHROM`, ``POS`, `REF` and `ALT` and produces `fullLocation`), 
// looks for matching `fullLocation` in the `genotiers` collection in MongoDB and 
// updates the matching document with the rest of the exomiser fields

// To run:
// minimum:
// node --no-warnings ./bin/add_exomiser_fields_to_genotiers.js -t ./testdata/exomiserVariantsHG001-NA12878-pFDA_S1_L001_100k_AR.variants.tsv
// full set:
// node --no-warnings ./bin/add_exomiser_fields_to_genotiers.js --tsvFile ./testdata/exomiserVariantsHG001-NA12878-pFDA_S1_L001_100k_AR.variants.tsv --databaseName clinical-dev --uri mongodb://localhost:27017

// functions
// closeConnection function closes the connection to MongoDB
function closeConnection() {
  mongoose.connection.close(function() {
    // console.log('Mongoose disconnected ');
  });
}
// makeFullLocation function creates `fullLocation` from `#CHROM`, ``POS`, `REF` and `ALT`
function makeFullLocation (chromosome, position, reference, alternative){
  var fullLocation;
  if(chromosome && position && reference && alternative){
    fullLocation = chromosome + ':' + position + '-' + reference + '-' + alternative;
  }
  return fullLocation;
}

// required packages
const { program } = require('commander');
const fs = require('fs')
const mongoose = require('mongoose');
require('./genotiers');

// Take inputs from command line
program
  .description('A script that, given a tsv file, retrieves the corresponding genotier from database and updates it with tsv file results')
  .option('-t, --tsvFile <type>', 'Tsv file with exomiser results')
  .option('-d, --databaseName <type>', 'Database name', "clinical-dev")
  .option('-u, --uri <type>', 'Uri to database', "mongodb://localhost:27017");
program.parse();
var tsvFilePath = program.opts().tsvFile
var dbName = program.opts().databaseName
var uri = program.opts().uri

// Extract file name from file path
var tsvFileName=tsvFilePath.split('/')[tsvFilePath.split('/').length-1].split('.')[0]
// Initiate log file
var logFileName = tsvFileName+'_addToDatabase.log'
fs.writeFileSync(logFileName, '');

// Connect to mongoDB
mongoose.connect(uri + '/' + dbName, {useNewUrlParser: true, useUnifiedTopology: true});

// If cannot connect beacause of error
mongoose.connection.on('error', function(err) {
  console.log('Mongoose connection error: ' + err);
});

// Read and split tsv file
var tsvFileContent = fs.readFileSync(tsvFilePath, 'utf8');
var tsvFileContentSplit = tsvFileContent.split('\n')
var header = tsvFileContentSplit[0].split('\t')
var i;
var count = 0;
// Iterate through header to get chromosome, pos, alt and ref
for(i=0;i<header.length;i++){
  item = header[i]
  if(item == '#CHROM'){
    var chromIndex = i;
  } else if(item == 'POS'){
    var posIndex = i;
  } else if(item == 'REF'){
    var refIndex= i;
  } else if(item == 'ALT'){
    var altIndex= i;
  }
}
// create GenotiersModel from required file
const GenotiersModel = mongoose.model('Genotiers');

// While connected to mongoDB run function
mongoose.connection.on('connected', function() {
  console.log('Mongoose connected to ' + uri);
  var j;
  // Iterate through the tsv file
  for(j=1;j<tsvFileContentSplit.length;j++){
    // Split each row by tab
    var row = tsvFileContentSplit[j].split('\t');
    // extract full location from row
    var fullLocation = makeFullLocation(row[chromIndex],row[posIndex],row[refIndex],row[altIndex])
    // find genotier in database by 'fullLocation'
    if(fullLocation){
      GenotiersModel
      .findOne({'fullLocation':fullLocation})
      .exec((err,genotier) => {
        if(err){
          console.log(err)
          if(count == tsvFileContentSplit.length-1){
            closeConnection()
          }
        } else if(!genotier){
          // console.log('No results')
          count = count+1;
          fs.appendFileSync(logFileName, 'Genotier for location: '+fullLocation+' not found \n')
          if(count == tsvFileContentSplit.length-1){
            closeConnection()
          }
        } else {
          if(genotier.length==0){
            // console.log('No results')
            count = count+1;
            fs.appendFileSync(logFileName, 'Genotier for location: '+fullLocation+' not found \n')
            if(count == tsvFileContentSplit.length-1){
              closeConnection()
            }
          } else {
            // if genotier found add all fields
            var k=0;
            for(k=0;k<header.length;k++){
              var value = header[k]
              if(value.includes('QUAL')){
                if(row[k]=='.'){
                  genotier.exomiserQual = '';
                } else {
                  genotier.exomiserQual = row[k]
                }
              } else if(value.includes('FILTER')){
                if(row[k]=='.'){
                  genotier.exomiserFilter = ''
                } else {
                  genotier.exomiserFilter = row[k]
                }
              } else if(value.includes('GENOTYPE')){
                if(row[k]=='.'){
                  genotier.exomiserGenotype = ''
                } else {
                  genotier.exomiserGenotype = row[k]
                }
              } else if(value.includes('HGVS')){
                if(row[k]=='.'){
                  genotier.exomiserHgvs = ''
                } else {
                  genotier.exomiserHgvs = row[k]
                }
              } else if(value.includes('COVERAGE')){
                if(row[k]=='.'){
                  genotier.exomiserCoverage = ''
                } else {
                  genotier.exomiserCoverage = row[k]
                }
              } else if(value.includes('FUNCTIONAL_CLASS')){
                if(row[k]=='.'){
                  genotier.exomiserFunctionalClass = ''
                } else {
                  genotier.exomiserFunctionalClass = row[k]
                }
              } else if(value==('EXOMISER_GENE')){
                if(row[k]=='.'){
                  genotier.exomiserGene = ''
                } else {
                  genotier.exomiserGene = row[k]
                }
              } else if(value.includes('EXOMISER_VARIANT_SCORE')){
                if(row[k]=='.'){
                  genotier.exomiserVariantScore = ''
                } else {
                  genotier.exomiserVariantScore = row[k]
                }
              } else if(value.includes('EXOMISER_GENE_PHENO_SCORE')){
                if(row[k]=='.'){
                  genotier.exomiserGenePhenoScore = ''
                } else {
                  genotier.exomiserGenePhenoScore = row[k]
                }
              } else if(value.includes('EXOMISER_GENE_VARIANT_SCORE')){
                if(row[k]=='.'){
                  genotier.exomiserGeneVariantScore = ''
                } else {
                  genotier.exomiserGeneVariantScore = row[k]
                }
              } else if(value.includes('EXOMISER_GENE_COMBINED_SCORE')){
                if(row[k]=='.'){
                  genotier.exomiserGeneCombinedScore = ''
                } else {
                  genotier.exomiserGeneCombinedScore = row[k]
                }
              } else if(value.includes('CADD(>0.483)')){
                if(row[k]=='.'){
                  genotier.exomiserCadd = ''
                } else {
                  genotier.exomiserCadd = row[k]
                }
              } else if(value.includes('POLYPHEN(>0.956|>0.446)')){
                if(row[k]=='.'){
                  genotier.exomiserPolyphen = ''
                } else {
                  genotier.exomiserPolyphen = row[k]
                }
              } else if(value.includes('MUTATIONTASTER(>0.94)')){
                if(row[k]=='.'){
                  genotier.exomiserMutationTaster = ''
                } else {
                  genotier.exomiserMutationTaster = row[k]
                }
              } else if(value.includes('SIFT(<0.06)')){
                if(row[k]=='.'){
                  genotier.exomiserSift = ''
                } else {
                  genotier.exomiserSift = row[k]
                }
              } else if(value.includes('REMM')){
                if(row[k]=='.'){
                  genotier.exomiserRemm = ''
                } else {
                  genotier.exomiserRemm = row[k]
                }
              } else if(value.includes('DBSNP_ID')){
                if(row[k]=='.'){
                  genotier.exomiserDbsnp = ''
                } else {
                  genotier.exomiserDbsnp = row[k]
                }
              } else if(value.includes('MAX_FREQUENCY')){
                if(row[k]=='.'){
                  genotier.exomiserMaxFreq = ''
                } else {
                  genotier.exomiserMaxFreq = row[k]
                }
              } else if(value.includes('DBSNP_FREQUENCY')){
                if(row[k]=='.'){
                  genotier.exomiserDbsnpFreq = ''
                } else {
                  genotier.exomiserDbsnpFreq = row[k]
                }
              } else if(value.includes('EVS_EA_FREQUENCY')){
                if(row[k]=='.'){
                  genotier.exomiserEvsEaFreq = ''
                } else {
                  genotier.exomiserEvsEaFreq = row[k]
                }
              } else if(value.includes('EVS_AA_FREQUENCY')){
                if(row[k]=='.'){
                  genotier.exomiserEvsAaFreq = ''
                } else {
                  genotier.exomiserEvsAaFreq = row[k]
                }
              } else if(value.includes('EXAC_AFR_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacAfrFreq = ''
                } else {
                  genotier.exomiserExacAfrFreq = row[k]
                }
              } else if(value.includes('EXAC_AMR_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacAmrFreq = ''
                } else {
                  genotier.exomiserExacAmrFreq = row[k]
                }
              } else if(value.includes('EXAC_EAS_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacEasFreq = ''
                } else {
                  genotier.exomiserExacEasFreq = row[k]
                }
              } else if(value.includes('EXAC_FIN_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacFinFreq = ''
                } else {
                  genotier.exomiserExacFinFreq = row[k]
                }
              } else if(value.includes('EXAC_NFE_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacNfeFreq = ''
                } else {
                  genotier.exomiserExacNfeFreq = row[k]
                }
              } else if(value.includes('EXAC_SAS_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacSasFreq = ''
                } else {
                  genotier.exomiserExacSasFreq = row[k]
                }
              } else if(value.includes('EXAC_OTH_FREQ')){
                if(row[k]=='.'){
                  genotier.exomiserExacOthFreq = ''
                } else {
                  genotier.exomiserExacOthFreq = row[k]
                }
              } else if(value.includes('CONTRIBUTING_VARIANT')){
                if(row[k]=='.'){
                  genotier.exomiserContributingVariant = ''
                } else {
                  genotier.exomiserContributingVariant = row[k]
                }
              }
            }
            // save modified field
            genotier.save((err,genotier) =>{
              if(err) {
                  console.log(err);
                  count = count+1;
                  if(count == tsvFileContentSplit.length-1){
                    closeConnection()
                  }
              } else {
                fs.appendFileSync(logFileName, 'Genotier for location: '+genotier.fullLocation+' had been changed \n')
                count = count+1;
                if(count == tsvFileContentSplit.length-1){
                  closeConnection()
                }
              }
            })
          }
        }
      })
    } else {
      console.log('No location found')
    }
  }
})