import random
import numpy as np
from collections import deque
import torch
import torch.nn as nn
import torch.optim as optim
from torch.utils.tensorboard import SummaryWriter

from simulation_env import WindowGameEnv, flatten_state
from model import DrinkingGameAgent

# Hyperparameters
NUM_EPISODES = 500           # Number of episodes to train
MAX_STEPS = 1000             # Max steps per episode (adjust as needed)
BATCH_SIZE = 32              # Batch size for training
GAMMA = 0.99                 # Discount factor
LEARNING_RATE = 1e-3         # Learning rate for optimizer
TARGET_UPDATE_FREQ = 1000    # Update target network every N steps
REPLAY_BUFFER_SIZE = 10000   # Maximum size of the replay buffer

# Exploration parameters
EPS_START = 1.0
EPS_END = 0.1
EPS_DECAY = 0.999  # Decay per episode

# Set up device
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class ReplayBuffer:
    def __init__(self, capacity):
        self.buffer = deque(maxlen=capacity)

    def push(self, state, action, reward, next_state, done):
        self.buffer.append((state, action, reward, next_state, done))

    def sample(self, batch_size):
        batch = random.sample(self.buffer, batch_size)
        state, action, reward, next_state, done = map(np.array, zip(*batch))
        return state, action, reward, next_state, done

    def __len__(self):
        return len(self.buffer)

def select_action(state, q_network, epsilon):
    """Epsilon-greedy action selection."""
    # state: np.ndarray (10,5,6)
    st = torch.tensor(state, dtype=torch.float32, device=device).unsqueeze(0)  # states
    vm = st[:,3:10,:,:].to(torch.bool)  # valid moves
    with torch.no_grad():
        _, q_values = q_network(st, vm)  # feed states and valid moves into the network
    return int(torch.argmax(q_values, dim=1).item())

def main():
    env = WindowGameEnv(observer=False)

    # Initialize Q-network and target network
    q_network = DrinkingGameAgent().to(device)
    target_network = DrinkingGameAgent().to(device)
    target_network.load_state_dict(q_network.state_dict())
    target_network.eval()

    optimizer = optim.Adam(q_network.parameters(), lr=LEARNING_RATE)
    replay_buffer = ReplayBuffer(REPLAY_BUFFER_SIZE)

    epsilon = EPS_START
    total_steps = 0

    writer = SummaryWriter(log_dir="runs")

    for episode in range(1, NUM_EPISODES + 1):
        state_dict = env.reset()
        state = flatten_state(state_dict)
        episode_reward = 0
        correct_count = 0
        wrong_count = 0
        invalid_count = 0

        for step in range(MAX_STEPS):
            total_steps += 1
            action = select_action(state, q_network, epsilon)
            next_state_dict, reward, done, debug = env.step_global(action)
            next_state = flatten_state(next_state_dict)
            episode_reward += reward

            # Count debug messages for different metrics
            if "Correct guess" in debug:
                correct_count += 1
            elif "Wrong guess" in debug:
                wrong_count += 1
            else:
                invalid_count += 1

            replay_buffer.push(state, action, reward, next_state, done)
            state = next_state

            if len(replay_buffer) >= BATCH_SIZE:
                states, actions, rewards, next_states, dones = replay_buffer.sample(BATCH_SIZE)

                # states: (B,10,5,6), actions: (B,), rewards: (B,), next_states: (B,10,5,6), dones: (B,)
                st = torch.tensor(states, dtype=torch.float32, device=device)  # (B,10,5,6)
                vm = st[:, 3:10, :, :].to(torch.bool)  # (B,7,5,6)
                at = torch.tensor(actions, dtype=torch.long, device=device).unsqueeze(1)  # (B,1)
                rw = torch.tensor(rewards, dtype=torch.float32, device=device).unsqueeze(1)  # (B,1)
                nst = torch.tensor(next_states, dtype=torch.float32, device=device)  # (B,10,5,6)
                dn = torch.tensor(dones, dtype=torch.float32, device=device).unsqueeze(1)  # (B,1)

                # Q(s,a)
                _, q_all = q_network(st, vm)  # (B,210)
                q_selected = q_all.gather(1, at)  # (B,1)

                # Q-targets using the target network
                with torch.no_grad():
                    nvm = nst[:, 3:10, :, :].to(torch.bool)
                    _, q_next = target_network(nst, nvm)  # (B,210)
                    max_q, _ = q_next.max(dim=1, keepdim=True)  # (B,1)
                    q_target = rw + GAMMA * max_q * (1 - dn)  # (B,1)

                # MSE loss & backprop
                loss = nn.MSELoss()(q_selected, q_target)

                optimizer.zero_grad()
                loss.backward()
                optimizer.step()

            if total_steps % TARGET_UPDATE_FREQ == 0:
                target_network.load_state_dict(q_network.state_dict())

            if done:
                break

        epsilon = max(EPS_END, epsilon * EPS_DECAY)

        if wrong_count == 0:
            ratio = correct_count
        else:
            ratio = correct_count / wrong_count

        # Log metrics to TensorBoard for this episode
        writer.add_scalar("Episode/Reward",episode_reward,episode)
        writer.add_scalar("Episode/Correct_Guesses",correct_count,episode)
        writer.add_scalar("Episode/Wrong_Guesses",wrong_count,episode)
        writer.add_scalar("Episode/Invalid_Guesses",invalid_count,episode)
        writer.add_scalar("Episode/Correct_to_Wrong_Ratio",ratio,episode)

        print(f"Episode {episode}: Reward = {episode_reward:.2f}, Correct = {correct_count}, Wrong = {wrong_count}, Invalid = {invalid_count}, Ratio = {ratio:.2f}, Epsilon = {epsilon:.3f}")

    writer.close()
    torch.save(q_network.state_dict(), "models/drinking_game_dqn.pth")
    print("Training complete and model saved.")

if __name__ == "__main__":
    main()
