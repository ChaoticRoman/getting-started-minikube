from fastapi import FastAPI, Request

app = FastAPI()


@app.get("/api/hello")
def hello(request: Request):
    user = request.headers.get("X-Ms-Client-Principal-Name")
    if user:
        return {"message": f"Hello, {user}!"}
    return {"message": "Hello, World!"}
