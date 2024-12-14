provider "aws" {
  region = "us-east-1" # Replace with your preferred region
}

# VPC
resource "aws_vpc" "my_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "MyVPC"
  }
}

# Public Subnet
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone = "us-east-1a"

  tags = {
    Name = "PublicSubnet"
  }
}

# Private Subnet
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.my_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "PrivateSubnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "my_igw" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "MyInternetGateway"
  }
}

# Public Route Table
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.my_igw.id
  }

  tags = {
    Name = "PublicRouteTable"
  }
}

# Associate Public Route Table with Public Subnet
resource "aws_route_table_association" "public_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_route_table.id
}

# Private Route Table
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  tags = {
    Name = "PrivateRouteTable"
  }
}

# NAT Gateway
resource "aws_eip" "nat_eip" {
  tags = {
    Name = "NAT_EIP"
  }
}

resource "aws_nat_gateway" "my_nat_gateway" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id

  tags = {
    Name = "My_NAT_Gateway"
  }
}

# Private Route for NAT Gateway
resource "aws_route" "private_route" {
  route_table_id         = aws_route_table.private_route_table.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.my_nat_gateway.id
}

# Associate Private Route Table with Private Subnet
resource "aws_route_table_association" "private_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_route_table.id
}

# DynamoDB Tables
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

# IAM Role for Lambda
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
      }
    ]
  })
}

# IAM Policy for Lambda
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

# Attach IAM Policy to Role
resource "aws_iam_role_policy_attachment" "lambda_policy_attachment" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
}

# Lambda Functions
resource "aws_lambda_function" "order_management_lambda" {
  function_name = "OrderManagementFunction"
  runtime       = "nodejs18.x"
  handler       = "index.handler"
  role          = aws_iam_role.lambda_execution_role.arn
  filename      = "C:/Users/kabo9/Downloads/terraform-project/OrderManagementFunction.zip"

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
  filename      = "lambda.zip"

  vpc_config {
    subnet_ids         = [aws_subnet.private_subnet.id]
    security_group_ids = [aws_security_group.lambda_security_group.id]
  }

  environment {
    variables = {
      INVENTORY_TABLE = aws_dynamodb_table.inventory_table.name
    }
  }
}

# API Gateway
resource "aws_apigatewayv2_api" "unified_api" {
  name          = "452-API"
  protocol_type = "HTTP"
}

# Integrations
resource "aws_apigatewayv2_integration" "inventory_lambda_integration" {
  api_id           = aws_apigatewayv2_api.unified_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.inventory_service_lambda.invoke_arn
}

resource "aws_apigatewayv2_integration" "order_lambda_integration" {
  api_id           = aws_apigatewayv2_api.unified_api.id
  integration_type = "AWS_PROXY"
  integration_uri  = aws_lambda_function.order_management_lambda.invoke_arn
}

# Routes
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
