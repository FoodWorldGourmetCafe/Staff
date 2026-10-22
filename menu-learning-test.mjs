import fs from 'node:fs';
import assert from 'node:assert/strict';
import {Window} from 'happy-dom';
const html=fs.readFileSync('index.html','utf8');
const w=new Window({settings:{disableJavaScriptEvaluation:true,disableJavaScriptFileLoading:true}});
w.document.write(html);
w.eval(html.match(/<script id="menu-learning-controls">([\s\S]*?)<\/script>/)[1]);
const d=w.document,notes=d.getElementById('notesGallery'),button=d.getElementById('notesToggle'),buttons=[...d.querySelectorAll('[data-portion-panel]')];
for(let i=0;i<3;i++){button.click();assert.equal(notes.hidden,false);assert.equal(button.getAttribute('aria-expanded'),'true');button.click();assert.equal(notes.hidden,true);}
buttons[0].click();assert.equal(d.getElementById('mealCompare').hidden,false);
buttons[1].click();assert.equal(d.getElementById('mealCompare').hidden,true);assert.equal(buttons[0].getAttribute('aria-expanded'),'false');assert.equal(d.getElementById('orderCompare').hidden,false);
buttons[1].click();assert.equal(d.getElementById('orderCompare').hidden,true);
assert.equal(notes.querySelectorAll('img').length,2);assert.equal(html.includes('IMG_0846'),false);assert.equal(d.querySelectorAll('#menu-learning-controls').length,1);
for(const el of d.querySelectorAll('#shorthand-learning [href],#shorthand-learning [src]')){const p=el.getAttribute('href')||el.getAttribute('src');if(/\.(jpg|zip)$/.test(p))assert.ok(fs.existsSync(p),p);}
console.log('Learning controls passed: repeat toggles, exclusive panels, ARIA states, two images and download paths.');
await w.happyDOM.abort();
