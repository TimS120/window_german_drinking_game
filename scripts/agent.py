import torch

from simulation_env import WindowGameEnv, flatten_state
from model import DrinkingGameAgent

class RLAgent:
    def __init__(self, device=torch.device("cpu")):
        self.device = device
        self.model = DrinkingGameAgent().to(self.device)  # initiate the model
        # self.model.load_state_dict(torch.load('path_to_weights.pth'))  # load model, if trained
        self.model.eval()

    def predict_action(self, env):
        """
        Predict an action given the current state from the environment.
        Args:
          - env: an instance of WindowGameEnv
        Returns:
          - action_index: an integer index (0-153) corresponding to the chosen action
          - probs: the output probability distribution (as a numpy array)
        """
        state = env._get_state()  # Get current state dictionary from the environment
        flat_state = flatten_state(state)  # Flatten the state ( Expected shape: (22,10) )
        state_tensor = torch.tensor(flat_state, dtype=torch.long, device=self.device).unsqueeze(0)
        logits = self.model(state_tensor)  # Shape: (1, 154)
        probs = torch.softmax(logits, dim=1)
        action_index = torch.argmax(probs, dim=1).item()  # Action choosing: here we use argmax
        return action_index, probs.detach().cpu().numpy()

if __name__ == "__main__":
    env = WindowGameEnv(observer=False)
    agent = RLAgent()
    state = env.reset()
    done = False
    while not done:
        action_index, probs = agent.predict_action(env)
        print(f"Agent selected action index: {action_index}")
        state, reward, done, debug = env.step_global(action_index)
        print(f"Reward: {reward}, Done: {done}, Debug: {debug}")
