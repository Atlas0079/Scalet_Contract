const fs=require('fs');
const {generate}=require('./generator.js');
const seed=process.argv[2]||'ALYBE-TILES',source=process.argv[3]||'32',out=process.argv[4]||'map.json';
const options=source.endsWith('.json')?JSON.parse(fs.readFileSync(source,'utf8')):{years:Number(source)};
const world=generate(seed,options);
if(world.validation.errors.length)throw new Error(world.validation.errors.join('\n'));
fs.writeFileSync(out,JSON.stringify(world));console.log(JSON.stringify({path:out,seed,years:world.options.years,size:[world.width,world.height],...world.stats,areas:world.areaSummary,warnings:world.warnings},null,2));
