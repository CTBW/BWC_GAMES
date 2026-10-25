(() => {
  let stage = 0;
  const scenario = document.querySelector('#scenario');
  const board = document.querySelector('#erosion-board');
  const notes = [
    ['The blood lands on an expendable outer terrace. The central approach and the stone circuit stay open. The stain is traversable for this full company turn.', 'The blood lands across the central approach. It is still traversable now, but its next two stages already show the cost of attacking here.'],
    ['Fungus blooms on the outer terrace. It now hurts and slows squads crossing it; the company can keep its useful central route.', 'Fungus blooms across the central route. The company must detour or spend an act cauterising it before Undercut.'],
    ['The outer terrace collapses into a shallow sinkhole. The sacrificed ground stays lost, while the central route and stable stone circuit remain.', 'The central soil collapses. The company still has the permanent stone circuit, but the longer rotation costs positioning and attack opportunities.'],
    ['A squad spent an act at the brazier before the collapse. The chosen fungal front becomes stable scorched earth, preserving this route.', 'Cauterising the threatened centre saves the route, but the act and access to the brazier were the price of the earlier burst position.']
  ];
  function draw() {
    const edge = scenario.value === 'edge';
    const affected = edge ? [[8,2],[9,2],[10,2],[8,3],[9,3],[10,3]] : [[5,3],[6,3],[5,4],[6,4],[5,5],[6,5]];
    const body = edge ? [[6,1],[7,1],[8,1],[6,2],[7,2],[6,3],[7,3]] : [[4,1],[5,1],[6,1],[4,2],[5,2],[6,2],[4,3]];
    const squads = [[3,4,'1'],[7,5,'2'],[4,6,'3'],[8,6,'4'],[2,6,'5'],[9,5,'6']];
    const inSet = (set,x,y) => set.some(p=>p[0]===x && p[1]===y);
    const fills=['#7f3f4c','#9d5863','#30242b','#ac956f'];
    const marks=['×','≋','▾','+'];
    let svg = '<svg viewBox="0 0 624 482" xmlns="http://www.w3.org/2000/svg" role="presentation">';
    for(let y=0;y<9;y++) for(let x=0;x<12;x++) {
      const stone=x===0||x===11||y===0||y===8;
      const infection=inSet(affected,x,y);
      const boss=inSet(body,x,y);
      const squad=squads.find(p=>p[0]===x&&p[1]===y);
      const brazier=(x===2&&y===3)||(x===9&&y===7);
      let fill=stone?'#647078':infection?fills[stage]:boss?'#3d2931':'#d3b783';
      let label=stone?'S':infection?marks[stage]:boss?'B':brazier?'F':'';
      if(squad){fill='#355d80';label=squad[2];}
      const px=12+x*50,py=12+y*50;
      svg += '<rect x="'+px+'" y="'+py+'" width="46" height="46" rx="4" fill="'+fill+'" stroke="#101115" stroke-width="1"/>';
      if(label) svg += '<text x="'+(px+23)+'" y="'+(py+30)+'" text-anchor="middle" fill="'+(brazier?'#23190e':'#ffffff')+'" font-size="'+(infection?'24':'16')+'" font-weight="600">'+label+'</text>';
    }
    svg+='</svg>';
    board.innerHTML=svg;
    const note=notes[stage][edge?0:1];
    document.querySelector('#stage-note').textContent=note;
    board.setAttribute('aria-label','Erosion diagram. '+note);
    document.querySelectorAll('[data-stage]').forEach(b=>b.setAttribute('aria-pressed',String(Number(b.dataset.stage)===stage)));
  }
  scenario.addEventListener('change',draw);
  document.querySelectorAll('[data-stage]').forEach(b=>b.addEventListener('click',()=>{stage=Number(b.dataset.stage);draw();}));
  document.querySelectorAll('.copy').forEach(button=>button.addEventListener('click',async()=>{
    const parent=button.closest('.prompt');
    try{await navigator.clipboard.writeText(parent.querySelector('pre').textContent);parent.querySelector('.copy-status').textContent='Copied full prompt.';}
    catch{parent.querySelector('.copy-status').textContent='Clipboard unavailable. Use Download prompt or select the text below.';}
  }));
  draw();
})();
