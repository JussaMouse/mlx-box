# Chatbot Frontend

This directory contains a simple, model-agnostic frontend to interact with the MLX chat server.

## How to run

1.  **Start the MLX chat server.**
    From the `models` directory, run:
    ```bash
    python chat-server.py
    ```
    Wait for the server to download the model and indicate that it's ready.

2.  **Serve the frontend.**
    Navigate to the `frontend` directory in your terminal and start a simple HTTP server. If you have Python 3, you can run:

    ```bash
    python3 -m http.server 8000
    ```

3.  **Open the chatbot.**
    Open your web browser and go to `http://localhost:8000`.

The chatbot will automatically connect to the server running on port 8080 and fetch the model name.

---

## Install as a macOS Service

To run the frontend as a background service that starts automatically on login, you can use the provided installation script.

1.  **Make the script executable:**
    ```bash
    chmod +x install-service.sh
    ```

2.  **Run the installer:**
    ```bash
    ./install-service.sh
    ```

The script will handle copying the files to `/Users/env/server/frontend`, creating a `launchd` service, and starting it. The frontend will then be available at `http://localhost:8000`. 