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
      INVENTORY_TABLE = "Inventory"
    }
  }
}
terraform {
  backend "s3" {
    bucket         = "my-terraform-state-bucket-452" # Replace with your unique bucket name
    key            = "terraform/state"
    region         = "us-east-1"
  }
}
# Unified API Gateway
resource "aws_apigatewayv2_api" "unified_api" {
  name          = "452-API" # API name updated here
  protocol_type = "HTTP"
}

# Lambda Permissions for UnifiedAPI (Inventory Service)
resource "aws_lambda_permission" "inventory_api_permission" {
  statement_id  = "AllowExecutionFromAPIGatewayInventory"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.inventory_service_lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.unified_api.execution_arn}/*/*"
}

# Lambda Permissions for UnifiedAPI (Order Management Service)
resource "aws_lambda_permission" "order_management_api_permission" {
  statement_id  = "AllowExecutionFromAPIGatewayOrder"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.order_management_lambda.arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.unified_api.execution_arn}/*/*"
}

# Integration for Inventory Lambda
resource "aws_apigatewayv2_integration" "inventory_lambda_integration" {
  api_id           = aws_apigatewayv2_api.unified_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.inventory_service_lambda.invoke_arn
  payload_format_version = "2.0"
}


# Integration for Order Management Lambda
resource "aws_apigatewayv2_integration" "order_lambda_integration" {
  api_id           = aws_apigatewayv2_api.unified_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.order_management_lambda.invoke_arn
}

# Routes for Inventory API
resource "aws_apigatewayv2_route" "inventory_routes" {
  for_each = {
    "GET /inventory/check/{itemID}" = "checkInventory"
    "DELETE /inventory/delete/{itemID}" = "deleteInventory"
    "POST /inventory/update" = "updateInventory"
  }

  api_id    = aws_apigatewayv2_api.unified_api.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.inventory_lambda_integration.id}"
}



# Routes for Order Management API
resource "aws_apigatewayv2_route" "order_routes" {
  for_each = toset(["POST /order/create", "DELETE /order/delete", "GET /order/status", "PUT /order/update"])

  api_id    = aws_apigatewayv2_api.unified_api.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.order_lambda_integration.id}"
}


# Deployment Stage
resource "aws_apigatewayv2_stage" "unified_api_stage" {
  api_id      = aws_apigatewayv2_api.unified_api.id
  name        = "dev"
  auto_deploy = true
}

# Output Unified API URL
output "unified_api_url" {
  value = aws_apigatewayv2_stage.unified_api_stage.invoke_url
}
