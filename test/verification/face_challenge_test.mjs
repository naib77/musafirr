import test from 'node:test';
import assert from 'node:assert/strict';
import {FaceChallenge} from '../../web/face/challenge.mjs';
const single = {count:1,centered:true,blink:0,yaw:0};
function driver(actions=['blink','left','right']) {
  const challenge=new FaceChallenge(actions); let time=0;
  return {challenge, frames(sample=single,n=5) {for(let i=0;i<n;i++) challenge.update({...single,...sample},time+=80);}};
}
test('a still face never completes a challenge',() => {
  const d=driver(); d.frames(single,100); assert.equal(d.challenge.index,0); assert.equal(d.challenge.phase,'action');
});
test('blink must reopen and both head turns must return to neutral',() => {
  const d=driver(); d.frames(); d.frames({blink:.9},1); assert.equal(d.challenge.index,0);
  d.frames(); assert.equal(d.challenge.index,1); d.frames(); d.frames({yaw:.3});
  assert.equal(d.challenge.index,1); d.frames(); assert.equal(d.challenge.index,2);
  d.frames(); d.frames({yaw:-.3}); assert.equal(d.challenge.complete,false);
  d.frames(); assert.equal(d.challenge.complete,true);
});
test('wrong direction and one-frame head spikes cannot pass',() => {
  const d=driver(['left','blink','right']); d.frames(); d.frames({yaw:-.3},20);
  d.frames({yaw:.3},1); d.frames(); assert.equal(d.challenge.index,0);
});
test('multiple faces, face loss, bad framing and stale frames reset progress',() => {
  for(const sample of [{count:0},{count:2},{centered:false}]) {
    const d=driver(); d.frames(); d.frames({blink:.9},1); d.frames(); assert.equal(d.challenge.index,1);
    d.frames(sample,sample.count === 2 ? 1 : 7); assert.equal(d.challenge.index,0);
  }
  const d=driver(); d.frames(); d.frames({blink:.9},1); d.frames();
  d.challenge.update(single,10000); assert.equal(d.challenge.index,0);
});
test('reject malformed action lists',() => {
  assert.throws(() => new FaceChallenge(['blink','blink','left']));
  assert.throws(() => new FaceChallenge(['smile']));
});
test('one missed detection does not erase completed actions', () => {
  const d=driver(); d.frames(); d.frames({blink:.9},1); d.frames();
  assert.equal(d.challenge.index,1);
  d.frames({count:0},1); d.frames();
  assert.equal(d.challenge.index,1);
});
test('a naturally offset neutral nose can still turn both ways', () => {
  const d=driver(['left','right','blink']);
  d.frames({yaw:.10},8); d.frames({yaw:.34},6); d.frames({yaw:.10},6);
  assert.equal(d.challenge.index,1);
  d.frames({yaw:.10},6); d.frames({yaw:-.14},6); d.frames({yaw:.10},6);
  assert.equal(d.challenge.index,2);
});
test('all six randomized action orders complete only after returning to neutral',()=>{
  for(const actions of [
    ['blink','left','right'],['blink','right','left'],['left','blink','right'],
    ['left','right','blink'],['right','left','blink'],['right','blink','left']]) {
    const d=driver(actions);
    for(const [i,action] of actions.entries()) {
      d.frames(); d.frames(action==='blink'?{blink:.9}:{yaw:action==='left'?.3:-.3});
      assert.equal(d.challenge.index,i);
      d.frames(); assert.equal(d.challenge.index,i+1);
    }
    assert.equal(d.challenge.complete,true);
  }
});
test('brief tracking loss invalidates the current gesture until a fresh neutral pose',()=>{
  const d=driver(['left','right','blink']); d.frames(); d.frames({yaw:.3});
  assert.equal(d.challenge.phase,'return');
  d.frames({count:0},1); d.frames();
  assert.equal(d.challenge.index,0); assert.equal(d.challenge.phase,'action');
});
test('a detected head turn tolerates small threshold jitter while held',()=>{
  const d=driver(['left','right','blink']); d.frames();
  d.frames({yaw:.24},1); d.frames({yaw:.18},4);
  assert.equal(d.challenge.phase,'return');
  d.frames(); assert.equal(d.challenge.index,1);
});
test('a natural blink that peaks near 0.5 completes the blink step',()=>{
  const d=driver(); d.frames(); d.frames({blink:.5},1); d.frames();
  assert.equal(d.challenge.index,1);
});
test('eyes that rest narrow can start, blink, and reopen',()=>{
  const d=driver(); d.frames({blink:.38},6); assert.equal(d.challenge.phase,'action');
  d.frames({blink:.5},1); assert.equal(d.challenge.phase,'action');
  d.frames({blink:.75},1); d.frames({blink:.38},6);
  assert.equal(d.challenge.index,1);
});
test('a squint below the blink threshold does not count',()=>{
  const d=driver(); d.frames({blink:.05},6); d.frames({blink:.28},5);
  assert.equal(d.challenge.index,0); assert.equal(d.challenge.phase,'action');
});
