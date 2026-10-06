"""Regenerate Python/Flutter public-history parity fixtures; run from ml/."""
import json
from pathlib import Path
import torch
from window_rl.cuda_environment import BatchedWindowEnv
from window_rl.contract import PASS_ACTION_INDEX


def board(values):
    pairs = values.reshape(5, 6, 2).tolist()
    return [[None if rank < 0 else round(rank * 8) * 4 + round(suit * 3)
             for rank, suit in row] for row in pairs]


def fixture(env, name):
    records = env.history_observation()[0]
    events = []
    for record in records[:-1]:
        if not bool(record.any()):
            continue
        action = record[60:65].tolist()
        action_index = PASS_ACTION_INDEX if action[0] else ((round(action[1]*4)*6 + round(action[2]*5))*2 + round(action[3]))*5 + round(action[4]*4)
        events.append(dict(boardBefore=board(record[:60]), actionIndex=action_index,
                           outcome=['correct', 'wrong', 'pass'][record[65:68].argmax().item()],
                           removedCards=board(record[68:128]),
                           mustSelectAdjacentToHandle=bool(record[-2]),turnCanEnd=bool(record[-1])))
    state = dict(players=['Ada'], currentPlayerIndex=0,turnStartFaceUp=5,
                 deck=env.deck[0,:env.deck_size[0]].tolist(),
                 cardGrid=[[None if v < 0 else v for v in row] for row in env.cards[0].tolist()],
                 faceUp=env.face_up[0].tolist(),pendingRemovals=[],pendingPenalty=0,
                 mustSelectAdjacentToHandle=bool(env.must_select_adjacent[0]),
                 turnCanEnd=bool(env.turn_can_end[0]),stats={'Ada':{}}, recentEvents=events)
    return dict(name=name,state=state,historyLength=env.history_length,
                history=records.flatten().tolist(),legalActions=env.action_mask()[0].nonzero().flatten().tolist())


def main():
    env=BatchedWindowEnv(dict(correct_guess=0,wrong_drink=-1,complete_game=0,**{'pass':0}),1,100,torch.device('cpu'),49,history_length=4,player_count=1)
    result=[fixture(env,'initial')]
    target,rank=env.cards[0,2,4]//4,env.cards[0,2,5]//4
    guess=0 if target>rank else 2 if target<rank else 1
    env.step(torch.tensor([160+guess]));result.append(fixture(env,'correct'))
    env.step(torch.tensor([300]));result.append(fixture(env,'pass'))
    # Exercise enough real transitions to wrap the bounded history, including
    # wrong/redeal events. Choosing actions here is test setup only.
    for index in range(8):
        env.step(env.action_mask().long().argmax(1))
        result.append(fixture(env,f'event_{index}'))
    env.reset();result.append(fixture(env,'reset'))
    Path('fixtures/recurrent_contract.json').write_text(json.dumps(result,separators=(',',':'))+'\n')

if __name__=='__main__': main()
