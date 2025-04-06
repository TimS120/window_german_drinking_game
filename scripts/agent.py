import torch
from simulation_env import WindowGameEnv, flatten_state  # Assuming simulation_env.py is in your project
from model import DrinkingGameAgent

class RLAgent:
    def __init__(self, device=torch.device("cpu")):
        self.device = device
        # Instantiate the model
        self.model = DrinkingGameAgent().to(self.device)
        # In practice, load pre-trained weights here:
        # self.model.load_state_dict(torch.load('path_to_trained_weights.pth'))
        self.model.eval()  # Set model to evaluation mode

    def predict_action(self, env):
        """
        Predict an action given the current state from the environment.
        Args:
          - env: an instance of WindowGameEnv
        Returns:
          - action_index: an integer index (0-153) corresponding to the chosen action
          - probs: the output probability distribution (as a numpy array)
        """
        # Obtain the current state dictionary from the environment
        state = env._get_state()
        # Flatten the state using the provided helper
        flat_state = flatten_state(state)  # Expected shape: (22,)
        # Convert the numpy array to a torch tensor (cast to long since our embedding expects integers)
        state_tensor = torch.tensor(flat_state, dtype=torch.long, device=self.device).unsqueeze(0)
        # Forward pass through the model
        logits = self.model(state_tensor)  # Shape: (1, 154)
        probs = torch.softmax(logits, dim=1)
        # Choose an action; here we use argmax (alternatively, sample from the distribution)
        action_index = torch.argmax(probs, dim=1).item()
        return action_index, probs.detach().cpu().numpy()

if __name__ == "__main__":
    # Quick example usage
    env = WindowGameEnv(observer=False)
    agent = RLAgent()
    state = env.reset()
    done = False
    while not done:
        action_index, probs = agent.predict_action(env)
        print(f"Agent selected action index: {action_index}")
        state, reward, done, debug = env.step_global(action_index)
        print(f"Reward: {reward}, Done: {done}, Debug: {debug}")
