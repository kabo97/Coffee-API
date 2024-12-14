provider "aws" {
  region = "us-east-1" # Replace with your preferred region
}
resource "aws_dynamodb_table" "orders_table" {
  name           = "OrdersTable"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "orderId"

  attribute {
    name = "orderId"
    type = "S"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
resource "aws_dynamodb_table" "inventory_table" {
  name           = "Inventory"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "ItemID"

  attribute {
    name = "ItemID"
    type = "S"
  }
  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}
resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name        = "lambda-dynamodb-policy"
  description = "Policy to allow Lambda to access DynamoDB tables"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:DeleteItem"
        ],
        Effect   = "Allow",
        Resource = [
          aws_dynamodb_table.orders_table.arn,
          aws_dynamodb_table.inventory_table.arn
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}
resource "aws_lambda_function" "order_management_lambda" {
  function_name = "OrderManagementFunction"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = "C:/Users/kabo9/Downloads/terraform-project/OrderManagementFunction.zip"
  layers        = ["arn:aws:lambda:us-east-1:481665116666:layer:node:1"]

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.orders_table.name
    }
  }
}
resource "aws_lambda_function" "inventory_service_lambda" {
  function_name = "InventoryServiceLambda1"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = "C:/Users/kabo9/Downloads/terraform-project/InventoryServiceFunction.zip" # Update with the correct file path
  layers        = ["arn:aws:lambda:us-east-1:481665116666:layer:node:1"]

  environment {
    variables = {
      INVENTORY_TABLE = aws_dynamodb_table.inventory_table.name
    }
  }
}
