// GET HPO TERMS FROM SAMPLE ID is a script 
// which looks for participant ID (more specifically the field `i`) in first collection specified and 
// then uses found id ('i') to find HP terms in second collection specified

// To run:
// minimum:
// node --no-warnings ./bin/get_hpo_terms_from_barcode.js --barcode 000000001
// full set:
// node ./bin/get_hpo_terms_from_barcode.js --barcode '000000001' --dbWithPatientSamples clinical-portal --uriWithPatientSamples mongodb://localhost:27017 --collectionPatientSamples patientsamples --dbWithParticipants cohort-browser --collectionParticipants participants --uriWithParticipants mongodb://localhost:27017

// required packages
const { program } = require('commander');
const fs = require('fs')

// Take inputs from command line
program
  .description('A script that, given a barcode, retrieves the corresponding participant ID (more specifically `i`) and HPO terms')
  .option('-b, --barcode <type>', '547300000450')
  .option('-ds, --dbWithPatientSamples <type>', 'Database containing the collection called "patientsamples"', "clinical-portal")
  .option('-us, --uriWithPatientSamples <type>', 'Uri to database containing the collection called "patientsamples"', "mongodb://localhost:27017")
  .option('-cs, --collectionPatientSamples <type>', 'Collection name for samples', "patientsamples")
  .option('-dp, --dbWithParticipants <type>', 'Database containing the collection called "participants"', "cohort-browser")
  .option('-up, --uriWithParticipants <type>', 'Uri to database containing the collection called "participants"', "mongodb://localhost:27017")
  .option('-cp, --collectionParticipants <type>', 'Collection name for participants', "participants")
program.parse();

var barcode = program.opts().barcode

var dbNameSamples = program.opts().dbWithPatientSamples
var uriSamples = program.opts().uriWithPatientSamples
var collectionSamples = program.opts().collectionPatientSamples

var dbNameParticipants = program.opts().dbWithParticipants
var uriParticipants = program.opts().uriWithParticipants
var collectionParticipants = program.opts().collectionParticipants

// initiate variables
var fileName = barcode+'_hpo_list.txt'

// initialise output file
fs.writeFileSync(fileName, '');
fs.appendFileSync(fileName, '# '+barcode+' \n')

// connect to mongoDB
var MongoClient = require('mongodb',{ useUnifiedTopology: true }).MongoClient;

// use promise to find first query results
var promise = new Promise((resolve, reject) => {
    MongoClient.connect(uriSamples,{poolSize: 1000}, function(err, db) {
        if (err) throw err;
        console.log('connected to database 1')
        var database = db.db(dbNameSamples);
        // prepare first query
        var query = { 'barcode': barcode };
        // query database
        database.collection(collectionSamples).find(query).toArray(function(err, results) {
            if(err) {
                reject(err)
                db.close()
            } else if(!results){
                reject('No results')
                db.close();
            } else if(Array.isArray(results)){
                if(results.length==0){
                    reject('No results')
                    db.close()
                } else {
                    // when results are created resolve promise
                    resolve(results[0].i)
                    db.close()
                }
            }
        });
    })
  });
// use results from first promise to query again
promise.then(firstQueryResults =>{
    MongoClient.connect(uriParticipants,{poolSize: 1000}, (err, db2) =>{
        if (err) throw err;
        console.log('connected to database 2')
        var database2 = db2.db(dbNameParticipants);
        // create new query
        var newQuery = {'i': firstQueryResults}
        // query database
        database2.collection(collectionParticipants).find(newQuery).toArray((err, results2)=> {
            if(err){
                console.log(err)
                db2.close()
            } else if(!results2){
                console.log('No results')
                db2.close()
            } else {
                if(results2.length == 0){
                    console.log('No results')
                    db2.close()
                } else {
                    results2.forEach(instance=>{
                        for (var key in instance) {
                            if (instance.hasOwnProperty(key)) {
                                // check if values have 'HP' in value
                                if(JSON.stringify(instance[key]).includes('HP')){
                                    var hpTerm = JSON.stringify(instance[key])
                                    if((JSON.stringify(instance[key]).includes('(')) && (JSON.stringify(instance[key]).includes(')'))){
                                        hpTerm = hpTerm.split('(')[1].split(')')[0]
                                    }
                                    // save results in output file
                                    fs.appendFileSync(fileName, hpTerm.replace(/['"]+/g, '')+'\n')
                                }
                            }
                        }
                    })
                    db2.close()
                }
            }
        })
    })
}).catch(err=>{
    console.log(err)
})
