import torch
import torch.nn as nn
import torch.nn.functional as F

class DrinkingGameAgent(nn.Module):
    def __init__(self, num_tokens=10, embed_dim=8, lstm_hidden=32, fc_hidden=64, output_dim=154):
        """
        Parameters:
          - num_tokens: number of possible token values (0 to 9 after remapping)
          - embed_dim: size of the embedding vector for each token
          - lstm_hidden: number of hidden units in the LSTM
          - fc_hidden: number of hidden units in the dense layer
          - output_dim: number of actions in the global action space (154)
        """
        super(DrinkingGameAgent, self).__init__()
        # Embedding layer to convert integer card values into dense vectors
        self.embedding = nn.Embedding(num_tokens, embed_dim)
        # LSTM layer to capture sequence (order) information from the 22 card positions
        self.lstm = nn.LSTM(input_size=embed_dim, hidden_size=lstm_hidden, batch_first=True)
        # Fully connected layers
        self.fc1 = nn.Linear(lstm_hidden, fc_hidden)
        self.fc2 = nn.Linear(fc_hidden, output_dim)

    def forward(self, x):
        """
        Forward pass.
        Args:
          - x: input tensor of shape (batch_size, 22) containing integers (0-9)
        Returns:
          - Logits for each action (shape: batch_size x 154)
        """
        x = self.embedding(x)  # Shape: (batch_size, 22, embed_dim)
        lstm_out, (hn, cn) = self.lstm(x)  # hn shape: (1, batch_size, lstm_hidden)
        # Use the final hidden state
        hn = hn.squeeze(0)  # Shape: (batch_size, lstm_hidden)
        x = F.relu(self.fc1(hn))
        logits = self.fc2(x)
        return logits

if __name__ == "__main__":
    # Quick test to verify model shape
    model = DrinkingGameAgent()
    dummy_input = torch.randint(0, 10, (1, 22))  # 1 sample, 22 card positions
    logits = model(dummy_input)
    print("Logits shape:", logits.shape)  # Should be (1, 154)
