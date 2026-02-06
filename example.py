"""Example module to test CodexConnector review."""

def calculate_average(numbers):
    total = 0
    for n in numbers:
        total = total + n
    avg = total / len(numbers)
    return avg

def find_user(users, id):
    for user in users:
        if user['id'] == id:
            return user
    return None

def process_data(data):
    result = []
    for item in data:
        if item != None:
            result.append(item.strip())
    return result
