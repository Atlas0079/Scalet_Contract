const fs=require('fs');
const {generate}=require('./generator.js');
const seed=process.argv[2]||'ALYBE-TILES',size=Number(process.argv[3]||960),out=process.argv[4]||'map.json';
if(![480,720,960].includes(size))throw new Error('Size must be 480, 720 or 960 metres');
const world=generate(seed,size);
if(world.validation.errors.length)throw new Error(world.validation.errors.join('\n'));
fs.writeFileSync(out,JSON.stringify(world));console.log(JSON.stringify({path:out,seed,...world.stats},null,2));
