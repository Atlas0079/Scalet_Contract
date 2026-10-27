'use strict';
importScripts('options.js?v=22.0','content.js?v=22.0','room-layouts.js?v=22.0','rail-station.js?v=22.0','planning.js?v=22.0','scene-objects.js?v=22.0','environment.js?v=22.0','generator.js?v=22.0');
onmessage=({data})=>{let lastPhase='',lastSent=0;const report=progress=>{const now=performance.now();if(progress.phase!==lastPhase||progress.done===progress.total||now-lastSent>=100){postMessage({type:'progress',progress});lastPhase=progress.phase;lastSent=now;}};
 try{const world=BubbleGenerator.generate(data.seed,data.options,report),runtime=world.runtime;postMessage({type:'result',world,runtime});}catch(error){postMessage({type:'error',error:error.message});}};
