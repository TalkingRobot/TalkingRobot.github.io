const canvas = document.getElementById('bgCanvas');
const ctx = canvas.getContext('2d');
let width = canvas.width = window.innerWidth;
let height = canvas.height = window.innerHeight;
const particles = [];

for(let i=0;i<100;i++){
  particles.push({
    x: Math.random()*width,
    y: Math.random()*height,
    r: Math.random()*2+1,
    dx: (Math.random()-0.5)*1,
    dy: (Math.random()-0.5)*1
  });
}

function animate(){
  ctx.clearRect(0,0,width,height);
  particles.forEach(p=>{
    ctx.beginPath();
    ctx.arc(p.x,p.y,p.r,0,Math.PI*2);
    ctx.fillStyle = "#00ffff";
    ctx.fill();
    p.x += p.dx;
    p.y += p.dy;
    if(p.x<0||p.x>width)p.dx*=-1;
    if(p.y<0||p.y>height)p.dy*=-1;
  });
  requestAnimationFrame(animate);
}
animate();
window.addEventListener('resize', ()=>{
  width = canvas.width = window.innerWidth;
  height = canvas.height = window.innerHeight;
});

