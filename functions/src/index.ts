import {randomInt} from "node:crypto";
import {initializeApp} from "firebase-admin/app";
import {getDatabase} from "firebase-admin/database";
import {HttpsError, onCall} from "firebase-functions/v2/https";

initializeApp();
const db = getDatabase();
const layout = [[true,true,true,true,true,false],[true,false,true,false,true,false],[true,true,true,true,true,true],[true,false,true,false,true,false],[true,true,true,true,true,false]];
const handle: Pos = [2, 5];
const corners = new Set(["0,0", "0,4", "4,0", "4,4"]);
const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
type Pos = [number, number];
type Guess = "higher" | "same" | "lower" | "inBetween" | "outside";
type Stats = {drinks:number; correct:number; wrong:number; changedCards:number; turns:number};
type State = {players:string[]; currentPlayerIndex:number; turnStartFaceUp:number; deck:number[]; cardGrid:(number|null)[][]; faceUp:boolean[][]; pendingRemovals:Pos[]; pendingPenalty:number; mustSelectAdjacentToHandle:boolean; turnCanEnd:boolean; pendingSamePosition:Pos|null; stats:Record<string,Stats>};
type Seat = {index:number; name:string; ownerUid:string|null};
type PrivateRoom = {hostUid:string; version:number; seats:Seat[]; state:State};
type StoredRoom = {private:PrivateRoom; public:PublicRoom};
type PublicRoom = {hostUid:string; version:number; seats:Seat[]; state:State};

function user(uid: string | undefined): string { if (!uid) throw new HttpsError("unauthenticated", "Sign in before using a room."); return uid; }
function names(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) throw new HttpsError("invalid-argument", `${label} must be a list.`);
  const result = value.map((item) => String(item).trim()).filter(Boolean);
  if (result.some((name) => name.length > 30)) throw new HttpsError("invalid-argument", "Names may contain at most 30 characters.");
  return result;
}
function unique(value: string[]): void {
  if (!value.length || value.length > 8 || new Set(value.map((name) => name.toLocaleLowerCase())).size !== value.length) throw new HttpsError("invalid-argument", "Use one to eight unique player names.");
}
function code(): string { return Array.from({length:6}, () => alphabet[randomInt(alphabet.length)]).join(""); }
function shuffle(cards: number[]): void { for (let i=cards.length-1;i>0;i--) { const j=randomInt(i+1); [cards[i],cards[j]]=[cards[j],cards[i]]; } }

function newState(players: string[]): State {
  const deck = Array.from({length:36}, (_, i) => i); shuffle(deck);
  const cardGrid:(number|null)[][] = layout.map((row) => row.map(() => null));
  const faceUp = layout.map((row) => row.map(() => false));
  for (let r=0;r<layout.length;r++) for (let c=0;c<layout[r].length;c++) if (valid([r,c])) {
    cardGrid[r][c]=deck.pop()!; faceUp[r][c]=corners.has(`${r},${c}`)||eq([r,c],handle);
  }
  const stats:Record<string,Stats>={}; players.forEach((name,i) => stats[name]={drinks:0,correct:0,wrong:0,changedCards:0,turns:i===0?1:0});
  return {players,currentPlayerIndex:0,turnStartFaceUp:5,deck,cardGrid,faceUp,pendingRemovals:[],pendingPenalty:0,mustSelectAdjacentToHandle:true,turnCanEnd:false,pendingSamePosition:null,stats};
}
function publish(room: PrivateRoom): PublicRoom {
  const state:State = structuredClone(room.state);
  state.cardGrid=state.cardGrid.map((row,r) => row.map((card,c) => state.faceUp[r][c] ? card : null));
  state.deck=[];
  return {hostUid:room.hostUid,version:room.version,seats:room.seats,state};
}

export const createRoom = onCall(async (request) => {
  const uid=user(request.auth?.uid);
  const local=names(request.data?.localPlayers,"localPlayers");
  const remote=names(request.data?.remoteSeats ?? [],"remoteSeats");
  const players=[...local,...remote]; unique(players);
  if (!local.length) throw new HttpsError("invalid-argument","At least one local player is required.");
  const seats=players.map((name,index):Seat => ({index,name,ownerUid:index<local.length?uid:null}));
  const privateRoom:PrivateRoom={hostUid:uid,version:1,seats,state:newState(players)};
  const stored:StoredRoom={private:privateRoom,public:publish(privateRoom)};
  for (let attempt=0;attempt<8;attempt++) { const roomCode=code(); const result=await db.ref(`rooms/${roomCode}`).transaction((current) => current ?? stored); if (result.committed) return {roomCode}; }
  throw new HttpsError("aborted","Could not reserve a room code. Try again.");
});

export const joinRoom = onCall(async (request) => {
  const uid=user(request.auth?.uid); const roomCode=String(request.data?.roomCode??"").trim().toUpperCase(); const seatName=String(request.data?.seatName??"").trim();
  if (!/^[A-Z2-9]{6}$/.test(roomCode)||!seatName) throw new HttpsError("invalid-argument","Enter a valid room code and seat name.");
  const result=await db.ref(`rooms/${roomCode}`).transaction((stored:StoredRoom|null) => {
    if (!stored?.private) return;
    const seat=stored.private.seats.find((item) => item.name===seatName);
    if (!seat) throw new HttpsError("not-found","That seat does not exist in this room.");
    if (seat.ownerUid&&seat.ownerUid!==uid) throw new HttpsError("already-exists","That seat is already claimed.");
    seat.ownerUid=uid; stored.public=publish(stored.private); return stored;
  });
  if (!result.committed) throw new HttpsError("not-found","Room not found."); return {roomCode};
});

export const submitAction = onCall(async (request) => {
  const uid=user(request.auth?.uid); const roomCode=String(request.data?.roomCode??"").trim().toUpperCase(); const expected=Number(request.data?.expectedVersion);
  if (!/^[A-Z2-9]{6}$/.test(roomCode)||!Number.isInteger(expected)) throw new HttpsError("invalid-argument","Invalid room action.");
  const result=await db.ref(`rooms/${roomCode}`).transaction((stored:StoredRoom|null) => {
    if (!stored?.private) return;
    const room=stored.private;
    if (room.version!==expected) throw new HttpsError("aborted","The room changed; wait for the latest board.");
    if (room.seats[room.state.currentPlayerIndex]?.ownerUid!==uid) throw new HttpsError("permission-denied","It is not your seat's turn.");
    action(room.state,request.data?.action); room.version++; stored.public=publish(room); return stored;
  });
  if (!result.committed) throw new HttpsError("not-found","Room not found."); return {version:expected+1};
});

type Option={type:"higherLower"|"inBetween";orientation:"horizontal"|"vertical";neighbors:Pos[];guesses:Guess[]};
function action(state:State, value:unknown):void {
  if (!value||typeof value!=="object") throw new HttpsError("invalid-argument","Missing game action."); const input=value as Record<string,unknown>;
  if (input.type==="guess") {
    if (state.pendingSamePosition||state.pendingRemovals.length) throw new HttpsError("failed-precondition","Finish the pending action first.");
    const position=pos(input.position); const orientation=input.orientation as "horizontal"|"vertical"; const guess=input.guess as Guess;
    const option=options(state,position).find((item) => item.orientation===orientation);
    if (!option||!option.guesses.includes(guess)) throw new HttpsError("invalid-argument","That guess is not valid for this card.");
    const card=at(state,position)!; let correct=false;
    if (option.type==="higherLower") { const compared=at(state,option.neighbors[0])!; correct=(guess==="higher"&&rank(card)>rank(compared))||(guess==="lower"&&rank(card)<rank(compared))||(guess==="same"&&rank(card)===rank(compared)); if (correct&&guess==="same") {state.pendingSamePosition=position;return;} }
    else { const first=at(state,option.neighbors[0])!; const second=at(state,option.neighbors[1])!; const between=rank(card)>=Math.min(rank(first),rank(second))&&rank(card)<=Math.max(rank(first),rank(second)); correct=(guess==="inBetween"&&between)||(guess==="outside"&&!between); }
    finish(state,position,correct); return;
  }
  if (input.type==="confirmSame") { const position=state.pendingSamePosition; if (!position) throw new HttpsError("failed-precondition","No same-rank guess is pending."); state.players.filter((name) => name!==current(state)).forEach((name) => state.stats[name].drinks++); state.pendingSamePosition=null; finish(state,position,true); return; }
  if (input.type==="confirmRemovals") { if (!state.pendingRemovals.length) throw new HttpsError("failed-precondition","No redeal is pending."); const removedHandle=state.pendingRemovals.some((item)=>eq(item,handle)); state.pendingRemovals.forEach((item)=>{const card=at(state,item);if(card!==null)state.deck.push(card);state.cardGrid[item[0]][item[1]]=null;state.faceUp[item[0]][item[1]]=false;}); state.mustSelectAdjacentToHandle=removedHandle; state.pendingRemovals=[];state.pendingPenalty=0;shuffle(state.deck);redeal(state);return; }
  if (input.type==="endTurn") { if (!state.turnCanEnd||state.pendingSamePosition||state.pendingRemovals.length) throw new HttpsError("failed-precondition","This turn cannot end yet."); const player=current(state);state.stats[player].changedCards+=openCount(state)-state.turnStartFaceUp;state.currentPlayerIndex=(state.currentPlayerIndex+1)%state.players.length;state.turnStartFaceUp=openCount(state);state.stats[current(state)].turns++;state.turnCanEnd=false;return; }
  throw new HttpsError("invalid-argument","Unknown game action.");
}
function options(state:State, position:Pos):Option[] { if(!valid(position)||up(state,position))return[];if(state.mustSelectAdjacentToHandle&&!adjacent(handle).some((item)=>eq(item,position)))return[];const horizontal=adjacent(position).filter((item)=>up(state,item)&&item[0]===position[0]).sort((a,b)=>a[1]-b[1]);const vertical=adjacent(position).filter((item)=>up(state,item)&&item[1]===position[1]).sort((a,b)=>a[0]-b[0]);const all:Option[]=[];addOption(all,horizontal,"horizontal");addOption(all,vertical,"vertical");const between=all.filter((item)=>item.type==="inBetween");return between.length?between:all; }
function addOption(all:Option[],neighbours:Pos[],orientation:"horizontal"|"vertical"):void {if(neighbours.length>=2)all.push({type:"inBetween",orientation,neighbors:[neighbours[0],neighbours[neighbours.length-1]],guesses:["inBetween","outside"]});else if(neighbours.length===1)all.push({type:"higherLower",orientation,neighbors:neighbours,guesses:["higher","same","lower"]});}
function finish(state:State,position:Pos,correct:boolean):void {const stats=state.stats[current(state)];state.faceUp[position[0]][position[1]]=true;if(correct){stats.correct++;state.mustSelectAdjacentToHandle=false;state.turnCanEnd=true;return;}state.pendingRemovals=connected(state,position);state.pendingPenalty=state.pendingRemovals.length;stats.wrong++;stats.drinks+=state.pendingPenalty;state.turnCanEnd=false;}
function connected(state:State,start:Pos):Pos[]{const found=new Map<string,Pos>();const queue=[start];while(queue.length){const item=queue.pop()!;if(found.has(item.join(",")))continue;found.set(item.join(","),item);adjacent(item).filter((next)=>up(state,next)).forEach((next)=>queue.push(next));}return[...found.values()];}
function redeal(state:State):void{for(let r=0;r<layout.length;r++)for(let c=0;c<layout[r].length;c++){const p:Pos=[r,c];if(valid(p)&&at(state,p)===null&&state.deck.length){state.cardGrid[r][c]=state.deck.pop()!;state.faceUp[r][c]=corners.has(`${r},${c}`)||eq(p,handle);}}}
function valid([r,c]:Pos):boolean{return r>=0&&r<layout.length&&c>=0&&c<layout[r].length&&layout[r][c];}
function adjacent([r,c]:Pos):Pos[]{return [[r-1,c],[r+1,c],[r,c-1],[r,c+1]].filter((item)=>valid(item as Pos)) as Pos[];}
function up(state:State,[r,c]:Pos):boolean{return state.faceUp[r][c];} function at(state:State,[r,c]:Pos):number|null{return state.cardGrid[r][c];} function current(state:State):string{return state.players[state.currentPlayerIndex];} function openCount(state:State):number{return state.faceUp.flat().filter(Boolean).length;} function rank(card:number):number{return Math.floor(card/4);} function eq(a:Pos,b:Pos):boolean{return a[0]===b[0]&&a[1]===b[1];}
function pos(value:unknown):Pos{if(!Array.isArray(value)||value.length!==2||!Number.isInteger(value[0])||!Number.isInteger(value[1]))throw new HttpsError("invalid-argument","Invalid card position.");return[Number(value[0]),Number(value[1])];}
